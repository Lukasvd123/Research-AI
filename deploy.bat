@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: Research-AI Server Launcher
:: Works on any Windows machine — installs Python if needed,
:: sets up a venv, installs deps, and runs the server detached
:: (like nohup on Linux). Server runs on localhost:8000.
:: ============================================================

set "PROJECT_DIR=%~dp0backend"
set "FRONTEND_DIR=%~dp0frontend"
set "VENV_DIR=%PROJECT_DIR%\.venv"
set "LOG_FILE=%PROJECT_DIR%\server.log"
set "PID_FILE=%PROJECT_DIR%\server.pid"
set "DEPLOY_LOG=%PROJECT_DIR%\deploy.log"
set "PYTHON_INSTALLER=%TEMP%\python_installer.exe"
set "PYTHON_VERSION=3.12.2"

:: Initialize deploy log
echo ============================================ > "%DEPLOY_LOG%"
echo  Deploy started: %date% %time% >> "%DEPLOY_LOG%"
echo ============================================ >> "%DEPLOY_LOG%"

:: -----------------------------------------------------------
:: 1. Find a working Python 3
:: -----------------------------------------------------------
call :log "[*] Checking for Python..."

set "PYTHON_CMD="

:: Try common python commands
where python >nul 2>&1
if %errorlevel%==0 (
    for /f "tokens=*" %%i in ('python --version 2^>^&1') do set "PY_VER=%%i"
    echo !PY_VER! | findstr /r "Python 3\." >nul 2>&1
    if !errorlevel!==0 (
        set "PYTHON_CMD=python"
        goto :found_python
    )
)

where python3 >nul 2>&1
if %errorlevel%==0 (
    set "PYTHON_CMD=python3"
    goto :found_python
)

where py >nul 2>&1
if %errorlevel%==0 (
    for /f "tokens=*" %%i in ('py -3 --version 2^>^&1') do set "PY_VER=%%i"
    echo !PY_VER! | findstr /r "Python 3\." >nul 2>&1
    if !errorlevel!==0 (
        set "PYTHON_CMD=py -3"
        goto :found_python
    )
)

:: -----------------------------------------------------------
:: 2. No Python found — download and install it
:: -----------------------------------------------------------
call :log "[!] Python 3 not found. Downloading Python %PYTHON_VERSION%..."
call :log "    This is a one-time setup step."

:: Use curl (built into Win10+) or powershell as fallback
set "PYTHON_URL=https://www.python.org/ftp/python/%PYTHON_VERSION%/python-%PYTHON_VERSION%-amd64.exe"

curl --version >nul 2>&1
if %errorlevel%==0 (
    curl -L -o "%PYTHON_INSTALLER%" "%PYTHON_URL%"
) else (
    powershell -Command "Invoke-WebRequest -Uri '%PYTHON_URL%' -OutFile '%PYTHON_INSTALLER%'"
)

if not exist "%PYTHON_INSTALLER%" (
    call :log "[X] Failed to download Python. Please install Python 3 manually from https://www.python.org"
    pause
    exit /b 1
)

call :log "[*] Installing Python %PYTHON_VERSION% (this may take a minute)..."
"%PYTHON_INSTALLER%" /quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 Include_launcher=1

:: Refresh PATH so the newly installed python is visible
set "PATH=%LOCALAPPDATA%\Programs\Python\Python312\;%LOCALAPPDATA%\Programs\Python\Python312\Scripts\;%PATH%"

del "%PYTHON_INSTALLER%" 2>nul

where python >nul 2>&1
if %errorlevel%==0 (
    set "PYTHON_CMD=python"
    goto :found_python
)

where py >nul 2>&1
if %errorlevel%==0 (
    set "PYTHON_CMD=py -3"
    goto :found_python
)

call :log "[X] Python installation succeeded but could not find it on PATH."
call :log "    Please restart this script or open a new terminal."
pause
exit /b 1

:found_python
for /f "tokens=*" %%i in ('!PYTHON_CMD! --version 2^>^&1') do (
    echo [OK] Found %%i
    echo [%time%] [OK] Found %%i >> "%DEPLOY_LOG%"
)

:: -----------------------------------------------------------
:: 3. Create virtual environment if it doesn't exist
:: -----------------------------------------------------------
if not exist "%VENV_DIR%\Scripts\python.exe" (
    call :log "[*] Creating virtual environment..."
    !PYTHON_CMD! -m venv "%VENV_DIR%"
    if !errorlevel! neq 0 (
        call :log "[X] Failed to create virtual environment."
        pause
        exit /b 1
    )
)

set "VENV_PYTHON=%VENV_DIR%\Scripts\python.exe"
set "VENV_PIP=%VENV_DIR%\Scripts\pip.exe"

:: -----------------------------------------------------------
:: 4. Install dependencies
:: -----------------------------------------------------------
call :log "[*] Installing dependencies..."
"%VENV_PYTHON%" -m pip install --quiet --upgrade pip >> "%DEPLOY_LOG%" 2>&1
"%VENV_PYTHON%" -m pip install --quiet -r "%PROJECT_DIR%\requirements.txt" >> "%DEPLOY_LOG%" 2>&1

if %errorlevel% neq 0 (
    call :log "[X] Failed to install dependencies."
    pause
    exit /b 1
)
call :log "[OK] Backend dependencies installed."

:: -----------------------------------------------------------
:: 5. Build frontend
:: -----------------------------------------------------------
call :log "[*] Checking for Node.js..."

set "NPM_CMD="
where npm >nul 2>&1
if %errorlevel%==0 (
    set "NPM_CMD=npm"
    goto :found_node
)

call :log "[X] Node.js / npm not found. Please install Node.js from https://nodejs.org"
pause
exit /b 1

:found_node
for /f "tokens=*" %%i in ('node --version 2^>^&1') do (
    echo [OK] Found Node.js %%i
    echo [%time%] [OK] Found Node.js %%i >> "%DEPLOY_LOG%"
)

call :log "[*] Installing frontend dependencies..."
pushd "%FRONTEND_DIR%"
npm install >> "%DEPLOY_LOG%" 2>&1
if !errorlevel! neq 0 (
    popd
    call :log "[X] Failed to install frontend dependencies."
    pause
    exit /b 1
)
call :log "[OK] Frontend dependencies installed."

call :log "[*] Building frontend..."
npm run build >> "%DEPLOY_LOG%" 2>&1
if !errorlevel! neq 0 (
    popd
    call :log "[X] Frontend build failed."
    pause
    exit /b 1
)
popd
call :log "[OK] Frontend built successfully."

:: -----------------------------------------------------------
:: 6. Kill any previous server instance
:: -----------------------------------------------------------
if exist "%PID_FILE%" (
    set /p OLD_PID=<"%PID_FILE%"
    echo [*] Stopping previous server (PID !OLD_PID!^)...
    echo [%time%] [*] Stopping previous server (PID !OLD_PID!^)... >> "%DEPLOY_LOG%"
    taskkill /PID !OLD_PID! /F >nul 2>&1
    del "%PID_FILE%" 2>nul
)

:: -----------------------------------------------------------
:: 7. Launch server detached (nohup-style)
:: -----------------------------------------------------------
call :log "[*] Starting server on http://localhost:8000 ..."
echo     Log file: %LOG_FILE%
echo [%time%]     Log file: %LOG_FILE% >> "%DEPLOY_LOG%"

start "" /b cmd /c ""%VENV_PYTHON%" "%PROJECT_DIR%\main.py" > "%LOG_FILE%" 2>&1"

:: Give it a moment to start and grab the PID
timeout /t 2 /nobreak >nul

:: Find the PID of the running uvicorn/python process
for /f "tokens=2" %%p in ('tasklist /fi "imagename eq python.exe" /fo list 2^>nul ^| findstr "PID"') do (
    set "SERVER_PID=%%p"
)

if defined SERVER_PID (
    echo !SERVER_PID!>"%PID_FILE%"
    echo.
    echo ========================================================
    echo   Server is running in the background!
    echo   URL:      http://localhost:8000
    echo   API docs: http://localhost:8000/docs
    echo   PID:      !SERVER_PID!
    echo   Log:      %LOG_FILE%
    echo.
    echo   To stop:  taskkill /PID !SERVER_PID! /F
    echo ========================================================
    echo. >> "%DEPLOY_LOG%"
    echo [%time%] ======================================================== >> "%DEPLOY_LOG%"
    echo [%time%]   Server is running in the background! >> "%DEPLOY_LOG%"
    echo [%time%]   URL:      http://localhost:8000 >> "%DEPLOY_LOG%"
    echo [%time%]   API docs: http://localhost:8000/docs >> "%DEPLOY_LOG%"
    echo [%time%]   PID:      !SERVER_PID! >> "%DEPLOY_LOG%"
    echo [%time%]   Log:      %LOG_FILE% >> "%DEPLOY_LOG%"
    echo [%time%]   To stop:  taskkill /PID !SERVER_PID! /F >> "%DEPLOY_LOG%"
    echo [%time%] ======================================================== >> "%DEPLOY_LOG%"
) else (
    echo.
    echo [OK] Server launched. Check %LOG_FILE% for output.
    echo     URL: http://localhost:8000
    echo. >> "%DEPLOY_LOG%"
    echo [%time%] [OK] Server launched. Check %LOG_FILE% for output. >> "%DEPLOY_LOG%"
    echo [%time%]     URL: http://localhost:8000 >> "%DEPLOY_LOG%"
)

endlocal
exit /b 0

:: -----------------------------------------------------------
:: Logging subroutine — prints to console and appends to log
:: -----------------------------------------------------------
:log
echo %~1
echo [%time%] %~1 >> "%DEPLOY_LOG%"
exit /b 0
