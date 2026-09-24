#requires -Version 5.1
# Keep this file UTF-8 with BOM so Windows PowerShell 5.1 reads Chinese correctly.
# Use the same encoding for console I/O and text piped to native commands.
$utf8Encoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = $utf8Encoding
try {
    [Console]::InputEncoding = $utf8Encoding
    [Console]::OutputEncoding = $utf8Encoding
} catch {
    Write-Warning "Unable to configure console UTF-8 encoding: $_"
}
# =====================================================================
#  hm-dianping 中间件一键启动 (PowerShell)
#  PowerShell 对代码页/编码的原生支持比 cmd 批处理更好，中文不会乱码。
#  用法（任选其一）：
#    1) 右键本文件 -> "使用 PowerShell 运行"
#    2) 在任意终端执行：
#         pwsh -NoProfile -ExecutionPolicy Bypass -File .\start_backend.ps1
#  脚本幂等：端口已在监听则跳过，可反复运行。
#  注意：MySQL 为 Windows 服务，需“管理员”身份执行 net start MySQL80（见 [3/3]）。
# =====================================================================

$ErrorActionPreference = 'SilentlyContinue'

function Test-Port {
    param([int]$Port)
    [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

Write-Host "========== hm-dianping middleware launcher ==========" -ForegroundColor Cyan

# ---------------- [1/3] Redis ----------------
$redisExe = 'D:\tools\redis\redis-server.exe'
$redisConf = 'D:\tools\redis\redis.windows.conf'
Write-Host ''

if (Test-Port 6379) {
    Write-Host '[1/3] Redis     : ' -NoNewline -ForegroundColor Green
    Write-Host '已在线 (127.0.0.1:6379)'
} else {
    Write-Host '[1/3] Redis     : 启动中...' -ForegroundColor Yellow
    if (Test-Path $redisExe) {
        Start-Process -FilePath $redisExe -ArgumentList "`"$redisConf`"" -WorkingDirectory (Split-Path $redisExe) -WindowStyle Minimized
        Write-Host '        已在独立窗口启动 redis-server'
    } else {
        Write-Host "        未找到 $redisExe，请先解压 Redis 到 D:\tools\redis" -ForegroundColor Red
    }
}

# ---------------- [2/3] Kafka ----------------
$kafkaHome = 'D:\tools\kafka_2.13-3.9.0'
$startBat  = "$kafkaHome\bin\windows\kafka-server-start.bat"
$config    = "$kafkaHome\config\kraft\server.properties"
Write-Host ''

if (Test-Port 9092) {
    Write-Host '[2/3] Kafka KRaft: ' -NoNewline -ForegroundColor Green
    Write-Host '已在线 (127.0.0.1:9092)'
} else {
    Write-Host '[2/3] Kafka KRaft: 启动中...' -ForegroundColor Yellow
    if (Test-Path $startBat) {
        Start-Process -FilePath 'cmd.exe' `
                      -ArgumentList '/c', "call `"$startBat`" `"$config`"" `
                      -WorkingDirectory $kafkaHome `
                      -WindowStyle Minimized
        Write-Host '        已在独立窗口启动 kafka-server'
    } else {
        Write-Host "        未找到 Kafka，请先解压 kafka_2.13-3.9.0 到 D:\tools" -ForegroundColor Red
    }
}

# ---------------- [3/3] MySQL ----------------
Write-Host ''

if (Test-Port 3306) {
    Write-Host '[3/3] MySQL    : ' -NoNewline -ForegroundColor Green
    Write-Host '已在线 (127.0.0.1:3306)'
} else {
    Write-Host '[3/3] MySQL    : 未监听 3306' -ForegroundColor Red
    Write-Host '        请以【管理员】打开终端后执行：  net start MySQL80'
}

# ---------------- 汇总 ----------------
Write-Host ''
$portsOK = (Test-Port 3306) -and (Test-Port 6379) -and (Test-Port 9092)
if ($portsOK) {
    Write-Host '全部就绪！' -ForegroundColor Green
    Write-Host '在 IntelliJ IDEA 中 Run HmDianPingApplication，然后访问 http://localhost:8081'
    Write-Host '详细步骤见仓库根目录 RUNBOOK.md'
} else {
    Write-Host '仍有中间件未就绪，请按上方提示处理后再试。' -ForegroundColor Yellow
}
