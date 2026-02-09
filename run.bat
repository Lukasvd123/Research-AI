@echo off
setlocal enabledelayedexpansion
title Research-AI Dev Launcher

:: ============================================================================
:: Research-AI Interactive Dev Launcher (Windows)
:: ============================================================================
:: Double-click friendly — opens cmd with interactive menu.
:: All containers communicate through localhost ports (like separate servers).
:: ============================================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: --- Container names ---
set "CADDY_CTR=research-ai-caddy-dev"
set "FRONTEND_CTR=research-ai-frontend-dev"
set "BACKEND_CTR=research-ai-backend-dev"
set "CADDY_IMG=research-ai-caddy-dev"
set "FRONTEND_IMG=research-ai-frontend-dev"
set "BACKEND_IMG=research-ai-backend-dev"

:: --- Ports ---
set "CADDY_PORT=8080"
set "FRONTEND_PORT=5173"
set "BACKEND_PORT=8000"

:: --- Runtime detection ---
set "RT="
set "KEEP_ALIVE=0"

goto :main_menu

:: ============================================================================
:: Main Menu
:: ============================================================================

:main_menu
cls
echo.
echo   ╔══════════════════════════════════════╗
echo   ║        Research-AI Dev Launcher       ║
echo   ╚══════════════════════════════════════╝
echo.

call :ensure_runtime
if !errorlevel! neq 0 goto :eof_pause

echo.
echo   What would you like to run?
echo     [1] Frontend only
echo     [2] Backend only
echo     [3] Both (frontend + backend + Caddy proxy)
echo     [4] Shut down all dev containers
echo     [5] Resume existing containers
echo.
choice /c 12345 /n /m "  Select option: "
set "MAIN_CHOICE=%errorlevel%"

if "%MAIN_CHOICE%"=="1" goto :run_frontend
if "%MAIN_CHOICE%"=="2" goto :run_backend
if "%MAIN_CHOICE%"=="3" goto :run_both
if "%MAIN_CHOICE%"=="4" goto :run_stop
if "%MAIN_CHOICE%"=="5" goto :run_resume
goto :main_menu

:run_frontend
call :lifetime_menu
call :start_frontend
call :start_caddy
goto :dev_panel

:run_backend
call :lifetime_menu
call :start_backend
call :start_caddy
goto :dev_panel

:run_both
call :lifetime_menu
call :start_backend
call :start_frontend
call :start_caddy
goto :dev_panel

:run_stop
call :stop_all
goto :eof_pause

:run_resume
call :resume_all
goto :dev_panel

:: ============================================================================
:: Lifetime Menu
:: ============================================================================

:lifetime_menu
echo.
echo   Container lifetime:
echo     [1] Keep alive while this window is open
echo     [2] Run indefinitely (survive after script closes)
echo.
choice /c 12 /n /m "  Select option: "
if !errorlevel! equ 1 (
    set "KEEP_ALIVE=1"
) else (
    set "KEEP_ALIVE=0"
)
goto :eof

:: ============================================================================
:: Runtime detection and auto-install
:: ============================================================================

:ensure_runtime
where podman >nul 2>&1
if !errorlevel! equ 0 (
    set "RT=podman"
    echo   [OK] Using container runtime: podman
    call :ensure_podman_machine
    goto :eof
)

:: Podman not found — offer to install
echo.
echo   [!] Podman is not installed.
echo.
echo   Would you like to download and install Podman Desktop?
echo     [1] Yes, download and install Podman
echo     [2] No, try Docker instead
echo.
choice /c 12 /n /m "  Select option: "
if !errorlevel! equ 1 goto :install_podman_windows

:: Try docker
where docker >nul 2>&1
if !errorlevel! equ 0 (
    set "RT=docker"
    echo   [OK] Using container runtime: docker
    goto :eof
)

echo   [ERROR] Neither podman nor docker found.
echo   Please install one manually and try again.
exit /b 1

:install_podman_windows
set "PODMAN_INSTALLER=%TEMP%\podman-setup.exe"
set "PODMAN_URL=https://github.com/containers/podman/releases/download/v5.7.1/podman-5.7.1-setup.exe"

echo.
echo   Downloading Podman installer...

:: Try curl first, then powershell
where curl >nul 2>&1
if !errorlevel! equ 0 (
    curl -L -o "%PODMAN_INSTALLER%" "%PODMAN_URL%"
) else (
    powershell -Command "Invoke-WebRequest -Uri '%PODMAN_URL%' -OutFile '%PODMAN_INSTALLER%'"
)

if not exist "%PODMAN_INSTALLER%" (
    echo   [ERROR] Download failed.
    exit /b 1
)

echo   Running installer... Please follow the prompts.
start /wait "" "%PODMAN_INSTALLER%"
del "%PODMAN_INSTALLER%" 2>nul

:: Refresh PATH and check again
set "PATH=%PATH%;%ProgramFiles%\RedHat\Podman;%LOCALAPPDATA%\Programs\Podman"
where podman >nul 2>&1
if !errorlevel! equ 0 (
    set "RT=podman"
    echo   [OK] Podman installed successfully!
    call :ensure_podman_machine
    goto :eof
)

echo   [ERROR] Podman still not found after install.
echo   You may need to restart this terminal.

:: Final fallback to docker
where docker >nul 2>&1
if !errorlevel! equ 0 (
    set "RT=docker"
    echo   [OK] Falling back to docker.
    goto :eof
)

echo   [ERROR] No container runtime available.
exit /b 1

:ensure_podman_machine
:: Windows podman requires a machine (Linux VM)
set "HAS_MACHINE=0"
for /f %%m in ('podman machine list --noheading 2^>nul') do set "HAS_MACHINE=1"
if "!HAS_MACHINE!"=="0" (
    echo   Initializing Podman machine (first-time setup)...
    podman machine init
    if !errorlevel! neq 0 (
        echo   [ERROR] Failed to initialize Podman machine.
        exit /b 1
    )
)

:: Check if machine is running
podman info >nul 2>&1
if !errorlevel! neq 0 (
    echo   Starting Podman machine...
    podman machine start
    if !errorlevel! neq 0 (
        echo   [ERROR] Failed to start Podman machine.
        exit /b 1
    )
)
echo   [OK] Podman machine is running.
goto :eof

:: ============================================================================
:: Container management — each container runs on its own port independently
:: ============================================================================

:start_caddy
echo.
echo   Building Caddy proxy image...
%RT% build -t %CADDY_IMG% -f "%SCRIPT_DIR%\dev\Containerfile.caddy" "%SCRIPT_DIR%"

:: Remove old container if it exists
%RT% rm -f %CADDY_CTR% >nul 2>&1

echo   Starting Caddy proxy on port %CADDY_PORT%...
%RT% run -d --name %CADDY_CTR% -p %CADDY_PORT%:80 %CADDY_IMG%

echo   [OK] Caddy proxy running on http://localhost:%CADDY_PORT%
goto :eof

:start_backend
echo.
echo   Building backend image...
%RT% build -t %BACKEND_IMG% -f "%SCRIPT_DIR%\dev\Containerfile.backend" "%SCRIPT_DIR%"

:: Remove old container if it exists
%RT% rm -f %BACKEND_CTR% >nul 2>&1

echo   Starting backend on port %BACKEND_PORT%...
%RT% run -d --name %BACKEND_CTR% ^
    -p %BACKEND_PORT%:8000 ^
    -e "CORS_ORIGINS=http://localhost:%CADDY_PORT%,http://localhost:%FRONTEND_PORT%" ^
    -v "%SCRIPT_DIR%\backend:/app" ^
    %BACKEND_IMG%

echo   [OK] Backend running on http://localhost:%BACKEND_PORT%
goto :eof

:start_frontend
echo.
echo   Building frontend image...
%RT% build -t %FRONTEND_IMG% -f "%SCRIPT_DIR%\dev\Containerfile.frontend" "%SCRIPT_DIR%"

:: Remove old container if it exists
%RT% rm -f %FRONTEND_CTR% >nul 2>&1

echo   Starting frontend on port %FRONTEND_PORT%...
%RT% run -d --name %FRONTEND_CTR% ^
    -p %FRONTEND_PORT%:5173 ^
    -v "%SCRIPT_DIR%\frontend\src:/app/src" ^
    -v "%SCRIPT_DIR%\frontend\public:/app/public" ^
    -v "%SCRIPT_DIR%\frontend\index.html:/app/index.html" ^
    -v "%SCRIPT_DIR%\frontend\vite.config.ts:/app/vite.config.ts" ^
    -v "%SCRIPT_DIR%\frontend\tsconfig.json:/app/tsconfig.json" ^
    -v "%SCRIPT_DIR%\frontend\tsconfig.app.json:/app/tsconfig.app.json" ^
    -v research-ai-node-modules:/app/node_modules ^
    -e "VITE_API_URL=http://localhost:%CADDY_PORT%/researchai-api" ^
    -e "VITE_BASE=/researchai/" ^
    %FRONTEND_IMG%

echo   [OK] Frontend running on http://localhost:%FRONTEND_PORT%
goto :eof

:stop_all
echo.
echo   Stopping all dev containers...
for %%c in (%CADDY_CTR% %FRONTEND_CTR% %BACKEND_CTR%) do (
    %RT% stop %%c >nul 2>&1
    %RT% rm %%c >nul 2>&1
    echo   [OK] Stopped %%c
)
echo.
echo   All containers stopped.
goto :eof

:resume_all
echo.
echo   Resuming dev containers...
for %%c in (%BACKEND_CTR% %FRONTEND_CTR% %CADDY_CTR%) do (
    %RT% start %%c >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [OK] Resumed %%c
    ) else (
        echo   [!] %%c does not exist — run 'Both' first.
    )
)
goto :eof

:: ============================================================================
:: Dev Panel
:: ============================================================================

:dev_panel
echo.
echo   ═══ Dev Panel ═══
echo.
echo   Access URLs:
echo     App (via Caddy):  http://localhost:%CADDY_PORT%/researchai/
echo     API (via Caddy):  http://localhost:%CADDY_PORT%/researchai-api/health
echo     Frontend direct:  http://localhost:%FRONTEND_PORT%
echo     Backend direct:   http://localhost:%BACKEND_PORT%
echo.
echo   Commands:
echo     [1] Show frontend logs
echo     [2] Show backend logs
echo     [3] Show caddy logs
echo     [4] Restart frontend
echo     [5] Restart backend
echo     [6] Rebuild frontend (full image rebuild)
echo     [7] Rebuild backend (full image rebuild)
echo     [8] Show container status
echo     [9] Open in browser
echo     [0] Stop all ^& exit
echo.
choice /c 1234567890 /n /m "  Select option: "
set "PANEL_CHOICE=%errorlevel%"

if "%PANEL_CHOICE%"=="1" goto :panel_frontend_logs
if "%PANEL_CHOICE%"=="2" goto :panel_backend_logs
if "%PANEL_CHOICE%"=="3" goto :panel_caddy_logs
if "%PANEL_CHOICE%"=="4" goto :panel_restart_frontend
if "%PANEL_CHOICE%"=="5" goto :panel_restart_backend
if "%PANEL_CHOICE%"=="6" goto :panel_rebuild_frontend
if "%PANEL_CHOICE%"=="7" goto :panel_rebuild_backend
if "%PANEL_CHOICE%"=="8" goto :panel_status
if "%PANEL_CHOICE%"=="9" goto :panel_browser
if "%PANEL_CHOICE%"=="10" goto :panel_exit
goto :dev_panel

:panel_frontend_logs
echo.
echo   --- Frontend logs (Ctrl+C to return) ---
%RT% logs -f %FRONTEND_CTR%
goto :dev_panel

:panel_backend_logs
echo.
echo   --- Backend logs (Ctrl+C to return) ---
%RT% logs -f %BACKEND_CTR%
goto :dev_panel

:panel_caddy_logs
echo.
echo   --- Caddy logs (Ctrl+C to return) ---
%RT% logs -f %CADDY_CTR%
goto :dev_panel

:panel_restart_frontend
echo   Restarting frontend...
%RT% restart %FRONTEND_CTR% >nul 2>&1
echo   [OK] Frontend restarted.
goto :dev_panel

:panel_restart_backend
echo   Restarting backend...
%RT% restart %BACKEND_CTR% >nul 2>&1
echo   [OK] Backend restarted.
goto :dev_panel

:panel_rebuild_frontend
echo   Rebuilding frontend...
%RT% rm -f %FRONTEND_CTR% >nul 2>&1
call :start_frontend
echo   [OK] Frontend rebuilt and started.
goto :dev_panel

:panel_rebuild_backend
echo   Rebuilding backend...
%RT% rm -f %BACKEND_CTR% >nul 2>&1
call :start_backend
echo   [OK] Backend rebuilt and started.
goto :dev_panel

:panel_status
echo.
echo   Container status:
for %%c in (%CADDY_CTR% %FRONTEND_CTR% %BACKEND_CTR%) do (
    %RT% container inspect --format "{{.State.Running}}" %%c >nul 2>&1
    if !errorlevel! equ 0 (
        echo     * %%c — running
    ) else (
        echo     - %%c — stopped or not created
    )
)
goto :dev_panel

:panel_browser
set "URL=http://localhost:%CADDY_PORT%/researchai/"
echo   Opening %URL% ...
start "" "%URL%"
goto :dev_panel

:panel_exit
call :stop_all
goto :eof_final

:: ============================================================================
:: Exit points
:: ============================================================================

:eof_pause
echo.
echo   Press any key to exit...
pause >nul
goto :eof_final

:eof_final
if "%KEEP_ALIVE%"=="1" (
    call :stop_all
)
endlocal
exit /b 0

:eof
goto :eof
