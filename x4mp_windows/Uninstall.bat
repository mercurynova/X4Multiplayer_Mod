@echo off
setlocal
title X4 Multiplayer - Uninstaller
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\uninstall.ps1"
echo.
pause
