@echo off
setlocal
chcp 65001 >nul
title Eski Cursor qayerda?

echo.
echo C:\Users\Xp\Desktop\projects va OneDrive Desktop qidiriladi.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0find-cursor-backup.ps1" %*
echo.
pause
