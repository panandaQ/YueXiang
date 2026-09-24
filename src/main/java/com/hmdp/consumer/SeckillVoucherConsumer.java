package com.hmdp.consumer;

import cn.hutool.json.JSONUtil;
import com.hmdp.entity.VoucherOrder;
import com.hmdp.service.IVoucherOrderService;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;

@Slf4j
@Component
public class SeckillVoucherConsumer {

    @Resource
    private IVoucherOrderService voucherOrderService;

    /**
     * 【秒杀链路消息队列使用】-3
     * Kafka 监听消费秒杀订单消息（消息体为 JSON 字符串，反序列化为 VoucherOrder）
     * AckMode.RECORD: 方法正常返回即提交 offset；抛异常则交给 KafkaConfig 的 DefaultErrorHandler
     * 按 FixedBackOff 策略重试，重试用尽后走告警 recoverer。
     */
    @KafkaListener(
            containerFactory = "seckillVoucherOrderKafkaListenerContainerFactory",
            topics = "seckill-voucher-order"
    )
    public void processMessage(ConsumerRecord<String, String> record) {
        try {
            // 获取消息内的数据(JSON -> VoucherOrder)
            VoucherOrder order = JSONUtil.toBean(record.value(), VoucherOrder.class);
            // 生成订单 扣减库存 等等操作
            voucherOrderService.createVoucherOrder(order);
        } catch (Exception e) {
            log.error("消费异常: topic={}, offset={}, 原因={}", record.topic(), record.offset(), e.getMessage());
            // 抛出异常由 errorHandler 执行 FixedBackOff 重试；重试用尽走告警
            throw new RuntimeException("消费秒杀订单失败", e);
        }
    }
}