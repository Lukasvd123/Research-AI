@echo off
title Research-AI Heartbeat
chcp 65001 >nul

:: Resolve WSL path for the project directory
set "WIN_DIR=%~dp0"
set "WIN_DIR=%WIN_DIR:~0,-1%"
for /f "tokens=1 delims=:" %%d in ("%WIN_DIR%") do set "DRIVE=%%d"
call set "REST=%%WIN_DIR:%DRIVE%:=%%"
set "REST=%REST:\=/%"
call :toLower DRIVE_L %DRIVE%
set "WSL_DIR=/mnt/%DRIVE_L%%REST%"

echo.
echo   +======================================+
echo   ^|     Research-AI Heartbeat Launcher    ^|
echo   +======================================+
echo.

:: Check WSL
wsl.exe echo ok >nul 2>&1
if %errorlevel% neq 0 (
    echo   [ERROR] WSL is not available.
    pause
    exit /b 1
)

:: Stop any existing heartbeat container
echo   Stopping previous heartbeat container (if any)...
wsl.exe bash -c "podman rm -f research-ai-heartbeat 2>/dev/null; true"

:: Start heartbeat via make target
echo   Starting heartbeat container...
echo.
wsl.exe bash -c "cd '%WSL_DIR%' && make heartbeat"

if %errorlevel% neq 0 (
    echo.
    echo   [ERROR] Failed to start heartbeat. Check the output above.
    pause
    exit /b 1
)

echo.
echo   Heartbeat is running in the background.
echo   To view logs:  wsl.exe bash -c "podman logs -f research-ai-heartbeat"
echo   To stop:       wsl.exe bash -c "podman rm -f research-ai-heartbeat"
echo.
exit /b 0

:toLower
:: Convert a single character to lowercase
set "%1=%2"
for %%c in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do (
    call set "%1=%%%1:%%c=%%c%%"
)
exit /b
