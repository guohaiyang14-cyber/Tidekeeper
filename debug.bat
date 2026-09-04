@echo off
setlocal EnableExtensions

rem ============================================================================
rem 潮汐守夜人 (Tidekeeper) — 双击以 Debug 模式启动游戏
rem 引擎：Godot 4.7.1  ｜  工程：godot_project/
rem
rem 自定义 Godot 路径（任选其一）：
rem   1. 复制 debug.local.bat.example 为 debug.local.bat 并修改
rem   2. 设置环境变量 GODOT_BIN（或写入 debug.local.bat）
rem
rem 可选：debug.local.bat 中设置 PAUSE_ON_EXIT=1，正常退出后也暂停控制台
rem ============================================================================

set "ROOT=%~dp0"
set "PROJECT=%ROOT%godot_project"
set "REQUIRED_GODOT_VERSION=4.7.1"

if exist "%ROOT%debug.local.bat" call "%ROOT%debug.local.bat"

if not defined GODOT_BIN (
    set "GODOT_BIN=E:\Godot\Godot_v4.7.1-stable_win64_console.exe"
)

if not exist "%GODOT_BIN%" (
    echo [错误] 找不到 Godot 可执行文件：
    echo   %GODOT_BIN%
    echo.
    echo 请设置环境变量 GODOT_BIN，或创建 debug.local.bat 指定路径。
    echo 可参考 debug.local.bat.example
    pause
    exit /b 1
)

if not exist "%PROJECT%\project.godot" (
    echo [错误] 找不到 Godot 工程：
    echo   %PROJECT%
    pause
    exit /b 1
)

set "GODOT_VERSION="
for /f "delims=" %%V in ('"%GODOT_BIN%" --version 2^>^&1') do set "GODOT_VERSION=%%V"
echo %GODOT_VERSION% | findstr /C:"%REQUIRED_GODOT_VERSION%" >nul
if errorlevel 1 (
    echo [错误] Godot 版本不匹配（需要 %REQUIRED_GODOT_VERSION%）：
    echo   %GODOT_VERSION%
    echo   %GODOT_BIN%
    pause
    exit /b 1
)

set "BOT_FLAG=--test-bot"
if defined TIDEKEEPER_NO_TEST_BOT set "BOT_FLAG=--no-test-bot"

echo 启动 Tidekeeper（Debug + TestBot 自动试玩）...
echo   Godot:   %GODOT_BIN%
echo   版本:    %GODOT_VERSION%
echo   工程:    %PROJECT%
echo   关闭机器人: 设置环境变量 TIDEKEEPER_NO_TEST_BOT=1 或 debug.bat --no-test-bot
echo   倍速:    默认 ×4（2~10）；debug.bat --bot-speed=8 或键 [ / ]
echo   灯塔:    每局随机 none/partial/full；--bot-lighthouse=full 可固定
echo.

"%GODOT_BIN%" --path "%PROJECT%" --debug %BOT_FLAG% %*
set "EXIT_CODE=%ERRORLEVEL%"

if %EXIT_CODE% NEQ 0 (
    echo.
    echo [错误] Godot 退出，代码: %EXIT_CODE%
    pause
) else if /I "%PAUSE_ON_EXIT%"=="1" (
    echo.
    echo [信息] 游戏已退出。
    pause
)

endlocal & exit /b %EXIT_CODE%
