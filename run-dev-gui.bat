@echo off
title Research-AI Dev Launcher (GUI)
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev\launcher.ps1" -GUI
if %errorlevel% neq 0 (
    echo.
    echo   Something went wrong. Check the output above.
    pause
)
