@echo off
setlocal
title X4 Multiplayer - Install Check
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\check.ps1"
echo.
pause
