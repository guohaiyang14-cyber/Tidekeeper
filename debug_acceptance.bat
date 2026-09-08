@echo off
setlocal EnableExtensions

rem ============================================================================
rem Tidekeeper — TestBot 验收总套件（对齐 docs/TestBot验收任务.md）
rem 默认：--bot-suite=acceptance --bot-speed=6
rem 额外参数原样转发给 debug.bat / Godot
rem ============================================================================

set "ROOT=%~dp0"
echo [TestBot] 验收套件 acceptance（清单兼容）
echo   查看结果: python tools/check_bot_acceptance.py --latest
echo   CombatLog: python tools/stats_combat_logs.py --latest 10 --completed-only
echo.

call "%ROOT%debug.bat" --bot-suite=acceptance --bot-speed=6 %*
set "EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %EXIT_CODE%
