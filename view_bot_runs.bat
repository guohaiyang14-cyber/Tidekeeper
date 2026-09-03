@echo off
setlocal EnableExtensions
rem View TestBot run summary from Godot userdata logs
rem Usage: view_bot_runs.bat
rem        view_bot_runs.bat --latest 10 --detail
rem        view_bot_runs.bat --all-logs
cd /d "%~dp0"
set "SCRIPT=%~dp0tools\view_bot_runs.py"

where py >nul 2>&1
if %ERRORLEVEL%==0 (
    py -3 "%SCRIPT%" %*
    goto after_run
)
where python >nul 2>&1
if %ERRORLEVEL%==0 (
    python "%SCRIPT%" %*
    goto after_run
)

echo [ERROR] Python not found. Install Python 3 or add py/python to PATH.
echo.
pause
exit /b 1

:after_run
set "EXIT_CODE=%ERRORLEVEL%"
echo.
pause
endlocal & exit /b %EXIT_CODE%
