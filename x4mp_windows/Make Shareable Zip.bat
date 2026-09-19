@echo off
setlocal
title X4 Multiplayer - Make Shareable Zip
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\make_zip.ps1"
echo.
pause
