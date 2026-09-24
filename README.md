<div align="center">
  <h1>悦享 · 本地生活服务后端</h1>
  <p>
    <img src="https://img.shields.io/badge/Java-8-orange" alt="Java 8">
    <img src="https://img.shields.io/badge/Spring%20Boot-2.3.12-green" alt="Spring Boot 2.3.12">
    <img src="https://img.shields.io/badge/MySQL-8.0-blue" alt="MySQL 8.0">
    <img src="https://img.shields.io/badge/Redis-cache-red" alt="Redis">
    <img src="https://img.shields.io/badge/Kafka-2.6-black" alt="Kafka">
  </p>
</div>

<br/>

悦享是一个本地生活服务后端学习项目，覆盖手机号验证码登录、商铺检索、探店笔记、关注关系、签到、优惠券与秒杀下单等场景。

项目的重点不在于堆砌接口，而是把高频读取、热点缓存、流量保护和秒杀订单这些容易出现并发问题的场景，落到可阅读的实现中：Redis 缓存、Lua 脚本、Kafka 异步消费、Caffeine 本地缓存与 Redisson 锁各自只承担合适的职责。

> 本项目用于学习本地生活服务场景下的 Spring Boot 与 Redis 实践。文档仅描述仓库中已经存在的实现；配置中的账号、地址和消费者组均为本地开发默认值，部署前请按环境调整。

## 这里记录什么

除了业务能力，本仓库更关注以下设计问题：

- 读多写少的商铺和优惠券数据，怎样避免缓存穿透与热点访问把数据库压垮？
- 秒杀资格校验怎样在高并发下同时保障库存不超卖与一人一单？
- 秒杀通过后，怎样把数据库写入从用户请求链路中拆出去？
- 面对突发访问，怎样用精确的滑动窗口限流保护服务？

## 核心能力

| 模块     | 已实现能力                                       | Redis / 基础设施实践         |
| -------- | ------------------------------------------------ | ---------------------------- |
| 用户     | 手机号验证码登录、Token 刷新、签到与连续签到统计 | Redis String、Hash、Bitmap   |
| 商铺     | 详情查询、更新、分类分页、附近商户检索           | 缓存空值、GEO 搜索、缓存失效 |
| 笔记     | 发布、点赞、热门列表、点赞用户、关注流分页       | ZSet 点赞榜与 Feed 流        |
| 关注     | 关注、取关、共同关注                             | Set 交集                     |
| 优惠券   | 普通券、秒杀券、按商户查询优惠券                 | Caffeine + Redis 两级缓存    |
| 秒杀订单 | 库存校验、一人一单、异步创建订单                 | Redis Lua、Kafka、Redisson   |
| 流量保护 | 注解式接口限流                                   | Redis ZSet 滑动窗口 + Lua    |

## 关键设计与取舍

### 1. 商铺缓存：先防穿透，再考虑热点重建

商铺详情是典型的读多写少数据。`CacheClient` 提供了三种缓存查询策略：

- **缓存穿透防护**：查询不到商铺时缓存空字符串，并使用较短 TTL；后续相同的无效请求不再直接访问数据库。
- **互斥锁重建**：缓存失效后仅持锁线程查询数据库并重建缓存，其余请求短暂等待后重试。
- **逻辑过期重建**：缓存值内保存逻辑过期时间；过期时由拿到锁的后台线程重建，而当前请求先返回旧值。

当前 `ShopServiceImpl` 的商铺详情查询启用的是缓存穿透防护策略。更新商铺时，事务写入数据库后删除对应的 Redis 缓存，下一次读取再加载新值。互斥锁与逻辑过期方案保留在 `CacheClient` 中，便于针对热点数据的可用性与一致性要求选择策略。

### 2. 优惠券列表：Caffeine + Redis 的两级缓存

秒杀优惠券列表属于更新不频繁、访问可能集中的数据。查询链路可配置为 MySQL、Redis 或 Caffeine；默认模式为 Caffeine：

```text
请求
  ↓
L1：Caffeine 本地缓存
  ↓ 未命中 / 刷新
L2：Redis
  ↓ 未命中
MySQL
  ↓
回填 Redis，再回填本地缓存
```

默认配置中，本地缓存写入 5 秒后触发刷新、10 分钟后硬过期；Redis 中的优惠券列表 TTL 为 30 分钟。这个设计降低热点数据对 Redis 的重复访问，同时将缓存模式、刷新时间与过期时间放在 `application.yaml` 中统一配置。

### 3. 秒杀下单：用 Redis Lua 做资格校验，用 Kafka 异步落库

秒杀请求最先进入 `seckill.lua`。Lua 脚本在 Redis 内一次完成以下操作：

1. 读取优惠券库存；库存不足时返回失败。
2. 检查该用户是否已在该券的订单集合中；已存在时返回重复下单。
3. 扣减 Redis 库存，并把用户 ID 写入优惠券订单 Set。

脚本成功后，服务生成订单 ID 并向 `seckill-voucher-order` 主题发送订单消息，接口立即返回订单 ID。Kafka 消费者接收 JSON 订单后，调用订单创建逻辑：以用户维度获取 Redisson 锁、使用 `stock > 0` 条件更新扣减数据库库存，再保存订单记录。

```text
客户端请求
  ↓
Redis Lua：库存校验 + 一人一单 + 预扣库存
  ↓
Kafka：seckill-voucher-order
  ↓
消费者：用户锁 → 条件扣减 MySQL 库存 → 创建订单
```

消费者采用 `AckMode.RECORD`：一条消息成功处理后提交 offset；处理异常会进入固定间隔重试，重试用尽后记录错误，供后续排查。这里的核心边界是：Redis 负责快速、原子地裁决抢购资格；Kafka 负责将数据库写操作从同步请求中解耦。

### 4. 滑动窗口限流：按方法、IP 或用户划分配额

`@RateLimiter` 注解配合 AOP 切面执行 `limiter.lua`。切面根据注解配置构造限流键，支持：

- **方法维度**：同一接口共享窗口配额；
- **IP 维度**：按客户端 IP 分别计数；
- **用户维度**：为接入用户身份维度预留扩展点。

Lua 脚本用 ZSet 保存请求时间戳和每次请求的唯一标识：先清理窗口外记录，再统计当前窗口数量；未到阈值则写入本次请求并设置过期时间，否则直接拒绝。所有判断与写入在 Redis 端原子执行，避免并发请求分别读取计数后同时放行。

### 5. Redis 数据结构如何贴合业务

| 场景             | 数据结构     | 用途                              |
| ---------------- | ------------ | --------------------------------- |
| 登录验证码       | String       | 保存短期验证码                    |
| 登录用户         | Hash         | 按 Token 保存脱敏用户信息并续期   |
| 商铺详情         | String       | JSON 缓存与空值缓存               |
| 附近商户         | GEO          | 按分类、坐标和距离查询商户        |
| 笔记点赞与关注流 | ZSet         | 记录点赞时间、按时间滚动分页 Feed |
| 共同关注         | Set          | 直接计算两个关注集合的交集        |
| 用户签到         | Bitmap       | 按月记录每日签到并统计连续天数    |
| 秒杀资格         | String + Set | 库存计数与已下单用户集合          |
| 限流             | ZSet         | 滑动时间窗口内的请求记录          |

## 技术栈

- Java 8、Spring Boot 2.3.12、Spring MVC、Spring AOP
- MyBatis-Plus、MySQL Connector/J 8.0.33
- Redis、Spring Data Redis、Lettuce、Redisson
- Apache Kafka、Spring Kafka
- Caffeine、Hutool、Lombok
