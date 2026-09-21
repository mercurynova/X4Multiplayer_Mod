@echo off
setlocal
title X4 Multiplayer - Collect Logs
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\collect_logs.ps1"
echo.
pause
