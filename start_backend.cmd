@echo off
REM ============================================================
REM  hm-dianping one-key middleware launcher
REM  Starts Redis & Kafka (starts a new console window each), 
REM  only if port is not already in use. Re-runnable / idempotent.
REM  MySQL (service MySQL80) needs admin, see step [3/3].
REM  NOTE: keep this file ASCII-only to avoid code-page mojibake.
REM ============================================================
setlocal

echo [1/3] Check / start Redis  (127.0.0.1:6379)
netstat -ano | findstr ":6379 " >nul 2>&1
if errorlevel 1 (
    start "hmdp-redis" /D D:\tools\redis D:\tools\redis\redis-server.exe D:\tools\redis\redis.windows.conf
    echo   Redis launching...
) else (
    echo   Redis already listening on 6379.
)
REM pause ~2s (ping trick avoids "timeout" stderr mojibake when no console tty)
ping 127.0.0.1 -n 3 >nul

echo [2/3] Check / start Kafka KRaft (127.0.0.1:9092)
netstat -ano | findstr ":9092 " >nul 2>&1
if errorlevel 1 (
    start "hmdp-kafka" /D D:\tools\kafka_2.13-3.9.0 cmd /c "bin\windows\kafka-server-start.bat config\kraft\server.properties"
    echo   Kafka launching...
) else (
    echo   Kafka already listening on 9092.
)
ping 127.0.0.1 -n 3 >nul

echo [3/3] Check MySQL (127.0.0.1:3306)
netstat -ano | findstr ":3306 " >nul 2>&1
if errorlevel 1 (
    echo   MySQL NOT listening on 3306.
    echo   Start it as ADMIN cmd:  net start MySQL80
) else (
    echo   MySQL already listening on 3306.
)

echo.
echo Next step: in IntelliJ IDEA, Run HmDianPingApplication, then open http://localhost:8081
echo (For full instructions see RUNBOOK.md in the repo root.)
endlocal
