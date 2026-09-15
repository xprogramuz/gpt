@echo off
setlocal
chcp 65001 >nul
title Cursor ni eski holatiga qaytarish

echo.
echo Cursor yopiladi va backupdan tiklanadi.
echo Backup: C:\Users\Xp\Desktop\projects\cursor-backup
echo.
echo Davom etish uchun istalgan tugmani bosing. Bekor qilish: Ctrl+C
pause >nul

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore-cursor.ps1" %*
set ERR=%ERRORLEVEL%

echo.
if %ERR% NEQ 0 (
  echo Tiklash xato bilan tugadi. Kod: %ERR%
) else (
  echo Tayyor. Endi Cursor ni ochishingiz mumkin.
)
echo.
pause
exit /b %ERR%
