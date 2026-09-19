@echo off
setlocal
title X4 Multiplayer - Installer
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install.ps1"
echo.
pause
