@echo off
setlocal enabledelayedexpansion

:: --- Configuration ---
set POD_NAME=research-ai-dev
set FRONTEND_CTR=research-ai-frontend-dev
set BACKEND_CTR=research-ai-backend-dev
set FRONTEND_IMG=research-ai-frontend-dev
set BACKEND_IMG=research-ai-backend-dev
set FRONTEND_PORT=5173
set BACKEND_PORT=8000

:: --- Auto-detect container runtime ---
where podman >nul 2>&1
if %errorlevel% neq 0 goto :try_docker

set RT=podman
set USE_POD=1

:: Check if any podman machine exists by counting lines from machine list
set "HAS_MACHINE=0"
for /f %%m in ('podman machine list --noheading 2^>nul') do set "HAS_MACHINE=1"
if "!HAS_MACHINE!"=="0" (
    echo No Podman machine found, initializing...
    podman machine init
    if !errorlevel! neq 0 (
        echo Error: failed to initialize Podman machine
        exit /b 1
    )
)

:: Check if podman daemon is reachable (machine is running)
podman info >nul 2>&1
if !errorlevel! neq 0 (
    echo Starting Podman machine...
    podman machine start
    if !errorlevel! neq 0 (
        echo Error: failed to start Podman machine
        exit /b 1
    )
)

goto :found_runtime

:try_docker
where docker >nul 2>&1
if %errorlevel% equ 0 (
    set RT=docker
    set USE_POD=0
    goto :found_runtime
)
echo Error: neither podman nor docker found in PATH
exit /b 1

:found_runtime
echo Using container runtime: %RT%

set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

if "%VITE_API_URL%"=="" set VITE_API_URL=http://localhost:%BACKEND_PORT%

if "%~1"=="" goto :usage
if "%~1"=="backend" goto :mode_backend
if "%~1"=="frontend" goto :mode_frontend
if "%~1"=="stop" goto :mode_stop
if "%~1"=="rebuild" goto :mode_rebuild
goto :usage

:mode_backend
call :ensure_pod
call :ensure_backend
call :ensure_frontend
echo.
echo Both services running in pod %POD_NAME%:
echo   Frontend: http://localhost:%FRONTEND_PORT%
echo   Backend:  http://localhost:%BACKEND_PORT%
goto :eof

:mode_frontend
call :ensure_pod
call :ensure_frontend
goto :eof

:mode_stop
echo Stopping pod %POD_NAME%...
if "%USE_POD%"=="1" (
    %RT% pod stop %POD_NAME% >nul 2>&1
    echo Pod stopped.
) else (
    %RT% stop %FRONTEND_CTR% >nul 2>&1
    %RT% stop %BACKEND_CTR% >nul 2>&1
    echo Containers stopped.
)
goto :eof

:mode_rebuild
echo Tearing down pod and containers for a clean rebuild...
if "%USE_POD%"=="1" (
    %RT% pod rm -f %POD_NAME% >nul 2>&1
) else (
    %RT% rm -f %FRONTEND_CTR% >nul 2>&1
    %RT% rm -f %BACKEND_CTR% >nul 2>&1
    %RT% network rm %POD_NAME% >nul 2>&1
)
echo Done. Run the script again with backend or frontend to rebuild.
goto :eof

:usage
echo Usage: %~nx0 ^<backend^|frontend^|stop^|rebuild^>
echo.
echo   backend   - Start BOTH frontend and backend in a pod
echo   frontend  - Start ONLY the frontend in a pod
echo   stop      - Stop the running pod/containers
echo   rebuild   - Remove pod and containers, then re-run to recreate
exit /b 1

:: =====================================================================
:: Functions
:: =====================================================================

:ensure_pod
if "%USE_POD%"=="1" (
    %RT% pod exists %POD_NAME% >nul 2>&1
    if !errorlevel! neq 0 (
        echo Creating pod: %POD_NAME%
        %RT% pod create --name %POD_NAME% ^
            -p %FRONTEND_PORT%:%FRONTEND_PORT% ^
            -p %BACKEND_PORT%:%BACKEND_PORT%
        if !errorlevel! neq 0 (
            echo Error: failed to create pod
            exit /b 1
        )
    ) else (
        echo Pod %POD_NAME% already exists.
        %RT% pod start %POD_NAME% >nul 2>&1
    )
) else (
    %RT% network inspect %POD_NAME% >nul 2>&1
    if !errorlevel! neq 0 (
        echo Creating network: %POD_NAME%
        %RT% network create %POD_NAME%
    )
)
goto :eof

:ensure_backend
echo Building backend image...
%RT% build -t %BACKEND_IMG% -f "%SCRIPT_DIR%\dev\Containerfile.backend" "%SCRIPT_DIR%"

:: Check if container already exists (works for both podman and docker)
%RT% container inspect %BACKEND_CTR% >nul 2>&1
if !errorlevel! equ 0 (
    echo Starting existing backend container...
    %RT% start %BACKEND_CTR% >nul 2>&1
) else (
    echo Creating backend container...
    if "%USE_POD%"=="1" (
        %RT% run -d --name %BACKEND_CTR% ^
            --pod %POD_NAME% ^
            -v "%SCRIPT_DIR%\backend:/app" ^
            %BACKEND_IMG%
    ) else (
        %RT% run -d --name %BACKEND_CTR% ^
            --network %POD_NAME% ^
            -p %BACKEND_PORT%:%BACKEND_PORT% ^
            -v "%SCRIPT_DIR%\backend:/app" ^
            %BACKEND_IMG%
    )
)
echo Backend running at http://localhost:%BACKEND_PORT%
goto :eof

:ensure_frontend
echo Building frontend image...
%RT% build -t %FRONTEND_IMG% -f "%SCRIPT_DIR%\dev\Containerfile.frontend" "%SCRIPT_DIR%"

:: Check if container already exists
%RT% container inspect %FRONTEND_CTR% >nul 2>&1
if !errorlevel! equ 0 (
    echo Starting existing frontend container...
    %RT% start %FRONTEND_CTR% >nul 2>&1
) else (
    echo Creating frontend container...
    if "%USE_POD%"=="1" (
        %RT% run -d --name %FRONTEND_CTR% ^
            --pod %POD_NAME% ^
            -v "%SCRIPT_DIR%\frontend\src:/app/src" ^
            -v "%SCRIPT_DIR%\frontend\public:/app/public" ^
            -v "%SCRIPT_DIR%\frontend\index.html:/app/index.html" ^
            -v "%SCRIPT_DIR%\frontend\vite.config.ts:/app/vite.config.ts" ^
            -v "%SCRIPT_DIR%\frontend\tsconfig.json:/app/tsconfig.json" ^
            -v "%SCRIPT_DIR%\frontend\tsconfig.app.json:/app/tsconfig.app.json" ^
            -v research-ai-node-modules:/app/node_modules ^
            -e "VITE_API_URL=%VITE_API_URL%" ^
            %FRONTEND_IMG%
    ) else (
        %RT% run -d --name %FRONTEND_CTR% ^
            --network %POD_NAME% ^
            -p %FRONTEND_PORT%:%FRONTEND_PORT% ^
            -v "%SCRIPT_DIR%\frontend\src:/app/src" ^
            -v "%SCRIPT_DIR%\frontend\public:/app/public" ^
            -v "%SCRIPT_DIR%\frontend\index.html:/app/index.html" ^
            -v "%SCRIPT_DIR%\frontend\vite.config.ts:/app/vite.config.ts" ^
            -v "%SCRIPT_DIR%\frontend\tsconfig.json:/app/tsconfig.json" ^
            -v "%SCRIPT_DIR%\frontend\tsconfig.app.json:/app/tsconfig.app.json" ^
            -v research-ai-node-modules:/app/node_modules ^
            -e "VITE_API_URL=%VITE_API_URL%" ^
            %FRONTEND_IMG%
    )
)
echo Frontend running at http://localhost:%FRONTEND_PORT%
goto :eof
