@echo off
setlocal enabledelayedexpansion

:: --- Auto-detect container runtime ---
where podman >nul 2>&1
if %errorlevel% equ 0 (
    set RT=podman
    goto :found_runtime
)
where docker >nul 2>&1
if %errorlevel% equ 0 (
    set RT=docker
    goto :found_runtime
)
echo Error: neither podman nor docker found in PATH
exit /b 1

:found_runtime
echo Using container runtime: %RT%

set SCRIPT_DIR=%~dp0
:: Remove trailing backslash
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

if "%VITE_API_URL%"=="" set VITE_API_URL=http://localhost:8000

if "%~1"=="" goto :usage
if "%~1"=="backend" goto :mode_backend
if "%~1"=="frontend" goto :mode_frontend
goto :usage

:mode_backend
call :start_backend
call :start_frontend
echo.
echo Both services running:
echo   Frontend: http://localhost:5173
echo   Backend:  http://localhost:8000
goto :eof

:mode_frontend
call :start_frontend
goto :eof

:usage
echo Usage: %~nx0 ^<backend^|frontend^>
echo.
echo   backend   - Start BOTH frontend and backend containers
echo   frontend  - Start ONLY the frontend container
exit /b 1

:: --- Functions ---

:stop_container
set "CNAME=%~1"
%RT% container exists %CNAME% >nul 2>&1
if %errorlevel% equ 0 (
    echo Stopping and removing existing container: %CNAME%
    %RT% stop %CNAME% >nul 2>&1
    %RT% rm %CNAME% >nul 2>&1
)
goto :eof

:start_frontend
call :stop_container research-ai-frontend-dev

echo Building frontend dev image...
%RT% build -t research-ai-frontend-dev -f "%SCRIPT_DIR%\dev\Containerfile.frontend" "%SCRIPT_DIR%"

echo Starting frontend dev container on port 5173...
%RT% run -d --name research-ai-frontend-dev ^
    -p 5173:5173 ^
    -v "%SCRIPT_DIR%\frontend\src:/app/src" ^
    -v "%SCRIPT_DIR%\frontend\public:/app/public" ^
    -v "%SCRIPT_DIR%\frontend\index.html:/app/index.html" ^
    -v "%SCRIPT_DIR%\frontend\vite.config.ts:/app/vite.config.ts" ^
    -v "%SCRIPT_DIR%\frontend\tsconfig.json:/app/tsconfig.json" ^
    -v "%SCRIPT_DIR%\frontend\tsconfig.app.json:/app/tsconfig.app.json" ^
    -v research-ai-node-modules:/app/node_modules ^
    -e "VITE_API_URL=%VITE_API_URL%" ^
    research-ai-frontend-dev

echo Frontend running at http://localhost:5173
goto :eof

:start_backend
call :stop_container research-ai-backend-dev

echo Building backend dev image...
%RT% build -t research-ai-backend-dev -f "%SCRIPT_DIR%\dev\Containerfile.backend" "%SCRIPT_DIR%"

echo Starting backend dev container on port 8000...
%RT% run -d --name research-ai-backend-dev ^
    -p 8000:8000 ^
    -v "%SCRIPT_DIR%\backend:/app" ^
    research-ai-backend-dev

echo Backend running at http://localhost:8000
goto :eof
