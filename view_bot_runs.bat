@echo off
setlocal EnableExtensions
rem 查看 TestBot 自动试玩局次（解析 Godot userdata 日志）
rem 用法: view_bot_runs.bat
rem       view_bot_runs.bat --latest 10 --detail
rem       view_bot_runs.bat --all-logs
set "ROOT=%~dp0"
set "SCRIPT=%ROOT%tools\view_bot_runs.py"

set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY (
    where python >nul 2>&1 && set "PY=python"
)
if not defined PY (
    echo [错误] 未找到 Python。请安装 Python 3，或确保 py/python 在 PATH 中。
    echo.
    pause
    exit /b 1
)

%PY% "%SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

rem 双击运行时窗口会立刻关掉，成功/失败都暂停以便查看输出
echo.
pause
endlocal & exit /b %EXIT_CODE%
