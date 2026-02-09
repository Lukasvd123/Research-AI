@echo off
setlocal enabledelayedexpansion
title Research-AI Dev Launcher
chcp 65001 >nul

:: ============================================================================
:: Research-AI Interactive Dev Launcher (Windows)
:: ============================================================================
:: Double-click friendly — opens cmd with interactive menu.
:: All containers communicate through localhost ports (like separate servers).
:: All actions are logged to the logs\ directory for crash diagnostics.
::
:: NOTE: In cmd.exe, "call :label" must NEVER appear inside parenthesized
:: if/else/for blocks — goto :eof inside the called label will exit the
:: entire calling context. All flow uses goto-based branching instead.
:: ============================================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: --- Log setup ---
set "LOGDIR=%SCRIPT_DIR%\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "TS=%date:~-10%_%time:~0,8%"
set "TS=%TS:/=-%"
set "TS=%TS::=-%"
set "TS=%TS: =0%"
set "LOGFILE=%LOGDIR%\run_%TS%.log"

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
set "STARTED_FRONTEND=0"
set "STARTED_BACKEND=0"

call :log "=========================================="
call :log "Research-AI Dev Launcher started"
call :log "Log file: %LOGFILE%"
call :log "=========================================="

goto :main_menu

:: ============================================================================
:: Logging — safe to call ONLY from top-level code (never inside if/for blocks)
:: ============================================================================

:log
echo   [%date% %time:~0,8%] %~1
echo [%date% %time:~0,8%] %~1 >> "%LOGFILE%" 2>nul
goto :eof

:log_silent
echo [%date% %time:~0,8%] %~1 >> "%LOGFILE%" 2>nul
goto :eof

:: ============================================================================
:: Main Menu
:: ============================================================================

:main_menu
cls
echo.
echo   ╔══════════════════════════════════════╗
echo   ║        Research-AI Dev Launcher      ║
echo   ╚══════════════════════════════════════╝
echo.

call :ensure_runtime
if !errorlevel! neq 0 goto :eof_pause

echo.
echo   What would you like to run?
echo     [1] Frontend only (+ Caddy proxy)
echo     [2] Backend (full stack)
echo     [3] Shut down all dev containers
echo     [4] Resume existing containers
echo.
choice /c 1234 /n /m "  Select option: "
set "MAIN_CHOICE=%errorlevel%"
call :log_silent "Main menu selection: %MAIN_CHOICE%"

if "%MAIN_CHOICE%"=="1" goto :run_frontend
if "%MAIN_CHOICE%"=="2" goto :run_backend
if "%MAIN_CHOICE%"=="3" goto :run_stop
if "%MAIN_CHOICE%"=="4" goto :run_resume
goto :main_menu

:run_frontend
set "STARTED_FRONTEND=1"
call :log_silent "Mode: Frontend only (+ Caddy)"
call :lifetime_menu
call :start_frontend
call :start_caddy
call :check_health
goto :dev_panel

:run_backend
set "STARTED_FRONTEND=1"
set "STARTED_BACKEND=1"
call :log_silent "Mode: Backend (full stack)"
call :lifetime_menu
call :start_backend
call :start_frontend
call :start_caddy
call :check_health
goto :dev_panel

:run_stop
call :log_silent "Mode: Shut down all"
call :stop_all
goto :eof_pause

:run_resume
set "STARTED_FRONTEND=1"
set "STARTED_BACKEND=1"
call :log_silent "Mode: Resume existing"
call :resume_all
call :check_health
goto :dev_panel

:: ============================================================================
:: Lifetime Menu — no call inside if blocks
:: ============================================================================

:lifetime_menu
echo.
echo   Container lifetime:
echo     [1] Keep alive while this window is open
echo     [2] Run indefinitely (survive after script closes)
echo.
choice /c 12 /n /m "  Select option: "
if !errorlevel! neq 1 goto :lifetime_indef
set "KEEP_ALIVE=1"
call :log_silent "Lifetime: Keep alive while window open"
goto :eof

:lifetime_indef
set "KEEP_ALIVE=0"
call :log_silent "Lifetime: Run indefinitely"
goto :eof

:: ============================================================================
:: Runtime detection and auto-install — no call inside if blocks
:: ============================================================================

:ensure_runtime
where podman >nul 2>&1
if !errorlevel! neq 0 goto :ert_no_podman

:: Podman found
set "RT=podman"
echo   [OK] Using container runtime: podman
call :log_silent "Runtime detected: podman"
call :ensure_podman_machine
goto :eof

:ert_no_podman
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
if !errorlevel! neq 0 goto :ert_no_runtime

set "RT=docker"
echo   [OK] Using container runtime: docker
call :log_silent "Runtime detected: docker"
goto :eof

:ert_no_runtime
call :log "ERROR: Neither podman nor docker found"
echo   [ERROR] Neither podman nor docker found.
echo   Please install one manually and try again.
exit /b 1

:install_podman_windows
call :log_silent "Attempting Podman installation..."
set "PODMAN_INSTALLER=%TEMP%\podman-setup.exe"
set "PODMAN_URL=https://github.com/containers/podman/releases/download/v5.7.1/podman-5.7.1-setup.exe"

echo.
echo   Downloading Podman installer...

:: Try curl first, then powershell
where curl >nul 2>&1
if !errorlevel! neq 0 goto :ert_dl_powershell
curl -L -o "%PODMAN_INSTALLER%" "%PODMAN_URL%"
goto :ert_dl_done

:ert_dl_powershell
powershell -Command "Invoke-WebRequest -Uri '%PODMAN_URL%' -OutFile '%PODMAN_INSTALLER%'"

:ert_dl_done
if not exist "%PODMAN_INSTALLER%" goto :ert_dl_failed

echo   Running installer... Please follow the prompts.
call :log_silent "Running Podman installer..."
start /wait "" "%PODMAN_INSTALLER%"
del "%PODMAN_INSTALLER%" 2>nul

:: Refresh PATH and check again
set "PATH=%PATH%;%ProgramFiles%\RedHat\Podman;%LOCALAPPDATA%\Programs\Podman"
where podman >nul 2>&1
if !errorlevel! neq 0 goto :ert_post_install_fail

set "RT=podman"
echo   [OK] Podman installed successfully!
call :log_silent "Podman installed successfully"
call :ensure_podman_machine
goto :eof

:ert_dl_failed
call :log "ERROR: Podman download failed"
echo   [ERROR] Download failed.
exit /b 1

:ert_post_install_fail
call :log "ERROR: Podman still not found after install"
echo   [ERROR] Podman still not found after install.
echo   You may need to restart this terminal.

:: Final fallback to docker
where docker >nul 2>&1
if !errorlevel! neq 0 goto :ert_no_runtime

set "RT=docker"
echo   [OK] Falling back to docker.
call :log_silent "Runtime fallback: docker"
goto :eof

:: ============================================================================
:: Podman machine management — no call inside if blocks
:: ============================================================================

:ensure_podman_machine
call :log_silent "Checking Podman machine status..."
set "HAS_MACHINE=0"
for /f %%m in ('podman machine list --noheading 2^>nul') do set "HAS_MACHINE=1"
if "!HAS_MACHINE!"=="1" goto :epm_check_running

:: No machine exists — initialize one
call :log_silent "Initializing Podman machine..."
echo   Initializing Podman machine (first-time setup)...
podman machine init >> "%LOGFILE%" 2>&1
if !errorlevel! neq 0 goto :epm_init_fail
call :log_silent "Podman machine initialized"

:epm_check_running
podman info >nul 2>&1
if !errorlevel! equ 0 goto :epm_ok

:: Machine not running — start it
call :log_silent "Starting Podman machine..."
echo   Starting Podman machine...
podman machine start >> "%LOGFILE%" 2>&1
if !errorlevel! neq 0 goto :epm_start_fail

:epm_ok
echo   [OK] Podman machine is running.
call :log_silent "Podman machine is running"
goto :eof

:epm_init_fail
call :log "ERROR: Failed to initialize Podman machine"
echo   [ERROR] Failed to initialize Podman machine.
exit /b 1

:epm_start_fail
call :log "ERROR: Failed to start Podman machine"
echo   [ERROR] Failed to start Podman machine.
exit /b 1

:: ============================================================================
:: Container management — no call inside if blocks
:: ============================================================================

:start_caddy
echo.
call :log_silent "Building Caddy proxy image..."
echo   Building Caddy proxy image...
%RT% build -t %CADDY_IMG% -f "%SCRIPT_DIR%\dev\Containerfile.caddy" "%SCRIPT_DIR%" 2>> "%LOGFILE%"
if !errorlevel! neq 0 goto :caddy_build_fail
call :log_silent "Caddy image built successfully"

:: Remove old container if it exists
%RT% rm -f %CADDY_CTR% >nul 2>&1

call :log_silent "Starting Caddy proxy on port %CADDY_PORT%..."
echo   Starting Caddy proxy on port %CADDY_PORT%...
%RT% run -d --name %CADDY_CTR% ^
    --add-host=host.containers.internal:host-gateway ^
    -p %CADDY_PORT%:80 ^
    %CADDY_IMG% >> "%LOGFILE%" 2>&1
if !errorlevel! neq 0 goto :caddy_run_fail

call :log_silent "Caddy proxy running on http://localhost:%CADDY_PORT%"
echo   [OK] Caddy proxy running on http://localhost:%CADDY_PORT%
goto :eof

:caddy_build_fail
call :log "ERROR: Caddy image build failed (details in log)"
goto :eof

:caddy_run_fail
call :log "ERROR: Failed to start Caddy container (details in log)"
goto :eof

:start_backend
echo.
call :log_silent "Building backend image..."
echo   Building backend image...
%RT% build -t %BACKEND_IMG% -f "%SCRIPT_DIR%\dev\Containerfile.backend" "%SCRIPT_DIR%" 2>> "%LOGFILE%"
if !errorlevel! neq 0 goto :backend_build_fail
call :log_silent "Backend image built successfully"

:: Remove old container if it exists
%RT% rm -f %BACKEND_CTR% >nul 2>&1

call :log_silent "Starting backend on port %BACKEND_PORT%..."
echo   Starting backend on port %BACKEND_PORT%...
%RT% run -d --name %BACKEND_CTR% ^
    -p %BACKEND_PORT%:8000 ^
    -e "CORS_ORIGINS=http://localhost:%CADDY_PORT%,http://localhost:%FRONTEND_PORT%" ^
    -v "%SCRIPT_DIR%\backend:/app" ^
    %BACKEND_IMG% >> "%LOGFILE%" 2>&1
if !errorlevel! neq 0 goto :backend_run_fail

call :log_silent "Backend running on http://localhost:%BACKEND_PORT%"
echo   [OK] Backend running on http://localhost:%BACKEND_PORT%
goto :eof

:backend_build_fail
call :log "ERROR: Backend image build failed (details in log)"
goto :eof

:backend_run_fail
call :log "ERROR: Failed to start backend container (details in log)"
goto :eof

:start_frontend
echo.
call :log_silent "Building frontend image..."
echo   Building frontend image...
%RT% build -t %FRONTEND_IMG% -f "%SCRIPT_DIR%\dev\Containerfile.frontend" "%SCRIPT_DIR%" 2>> "%LOGFILE%"
if !errorlevel! neq 0 goto :frontend_build_fail
call :log_silent "Frontend image built successfully"

:: Remove old container if it exists
%RT% rm -f %FRONTEND_CTR% >nul 2>&1

call :log_silent "Starting frontend on port %FRONTEND_PORT%..."
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
    %FRONTEND_IMG% >> "%LOGFILE%" 2>&1
if !errorlevel! neq 0 goto :frontend_run_fail

call :log_silent "Frontend running on http://localhost:%FRONTEND_PORT%"
echo   [OK] Frontend running on http://localhost:%FRONTEND_PORT%
goto :eof

:frontend_build_fail
call :log "ERROR: Frontend image build failed (details in log)"
goto :eof

:frontend_run_fail
call :log "ERROR: Failed to start frontend container (details in log)"
goto :eof

:: ============================================================================
:: Health Check — verifies containers are running and endpoints respond
:: ============================================================================

:check_health
echo.
call :log_silent "Running health checks..."
echo   Waiting for services to initialize (5s)...
timeout /t 5 /nobreak >nul
echo.
echo   ─── Health Check ───
echo.
set "HEALTH_OK=1"

:: --- Container status ---
set "_S=FAIL"
%RT% container inspect --format "{{.State.Running}}" %CADDY_CTR% 2>nul | findstr "true" >nul 2>&1
if !errorlevel! equ 0 set "_S=OK"
if "!_S!"=="FAIL" set "HEALTH_OK=0"
echo     [!_S!]  Caddy container

if "!STARTED_FRONTEND!"=="0" goto :hc_skip_fe_ctr
set "_S=FAIL"
%RT% container inspect --format "{{.State.Running}}" %FRONTEND_CTR% 2>nul | findstr "true" >nul 2>&1
if !errorlevel! equ 0 set "_S=OK"
if "!_S!"=="FAIL" set "HEALTH_OK=0"
echo     [!_S!]  Frontend container
:hc_skip_fe_ctr

if "!STARTED_BACKEND!"=="0" goto :hc_skip_be_ctr
set "_S=FAIL"
%RT% container inspect --format "{{.State.Running}}" %BACKEND_CTR% 2>nul | findstr "true" >nul 2>&1
if !errorlevel! equ 0 set "_S=OK"
if "!_S!"=="FAIL" set "HEALTH_OK=0"
echo     [!_S!]  Backend container
:hc_skip_be_ctr

:: --- HTTP endpoint checks (requires curl.exe) ---
where curl.exe >nul 2>&1
if !errorlevel! neq 0 goto :hc_no_curl

echo.

if "!STARTED_FRONTEND!"=="0" goto :hc_skip_fe_http
set "_S=FAIL"
curl.exe -sf -o nul http://localhost:%FRONTEND_PORT%/researchai/ 2>nul
if !errorlevel! equ 0 set "_S=OK"
if "!_S!"=="FAIL" set "HEALTH_OK=0"
echo     [!_S!]  Frontend direct — http://localhost:%FRONTEND_PORT%/researchai/
:hc_skip_fe_http

if "!STARTED_BACKEND!"=="0" goto :hc_skip_be_http
set "_S=FAIL"
curl.exe -sf -o nul http://localhost:%BACKEND_PORT%/health 2>nul
if !errorlevel! equ 0 set "_S=OK"
if "!_S!"=="FAIL" set "HEALTH_OK=0"
echo     [!_S!]  Backend direct — http://localhost:%BACKEND_PORT%/health
:hc_skip_be_http

:: Caddy proxy checks
if "!STARTED_FRONTEND!"=="0" goto :hc_skip_caddy_fe
set "_S=FAIL"
curl.exe -sf -o nul http://localhost:%CADDY_PORT%/researchai/ 2>nul
if !errorlevel! equ 0 set "_S=OK"
if "!_S!"=="FAIL" set "HEALTH_OK=0"
echo     [!_S!]  Caddy proxy → Frontend — http://localhost:%CADDY_PORT%/researchai/
:hc_skip_caddy_fe

if "!STARTED_BACKEND!"=="0" goto :hc_skip_caddy_be
set "_S=FAIL"
curl.exe -sf -o nul http://localhost:%CADDY_PORT%/researchai-api/health 2>nul
if !errorlevel! equ 0 set "_S=OK"
if "!_S!"=="FAIL" set "HEALTH_OK=0"
echo     [!_S!]  Caddy proxy → Backend — http://localhost:%CADDY_PORT%/researchai-api/health
:hc_skip_caddy_be

goto :hc_done

:hc_no_curl
echo.
echo     [SKIP] curl.exe not found — HTTP checks skipped (container checks only)

:hc_done
echo.
if "!HEALTH_OK!"=="1" echo   All services are healthy!
if "!HEALTH_OK!"=="0" echo   [!] Some checks failed — use Dev Panel to view container logs
call :log_silent "Health check complete (all_ok=!HEALTH_OK!)"
goto :eof

:: ============================================================================
:: Stop / Resume — unrolled loops to avoid call inside for blocks
:: ============================================================================

:stop_all
echo.
call :log_silent "Stopping all dev containers..."
echo   Stopping all dev containers...
%RT% stop %CADDY_CTR% >nul 2>&1
%RT% rm %CADDY_CTR% >nul 2>&1
echo   [OK] Stopped %CADDY_CTR%
%RT% stop %FRONTEND_CTR% >nul 2>&1
%RT% rm %FRONTEND_CTR% >nul 2>&1
echo   [OK] Stopped %FRONTEND_CTR%
%RT% stop %BACKEND_CTR% >nul 2>&1
%RT% rm %BACKEND_CTR% >nul 2>&1
echo   [OK] Stopped %BACKEND_CTR%
echo.
echo   All containers stopped.
call :log_silent "All containers stopped"
goto :eof

:resume_all
echo.
call :log_silent "Resuming dev containers..."
echo   Resuming dev containers...
%RT% start %BACKEND_CTR% >nul 2>&1
if !errorlevel! equ 0 (echo   [OK] Resumed %BACKEND_CTR%) else (echo   [!] %BACKEND_CTR% does not exist)
%RT% start %FRONTEND_CTR% >nul 2>&1
if !errorlevel! equ 0 (echo   [OK] Resumed %FRONTEND_CTR%) else (echo   [!] %FRONTEND_CTR% does not exist)
%RT% start %CADDY_CTR% >nul 2>&1
if !errorlevel! equ 0 (echo   [OK] Resumed %CADDY_CTR%) else (echo   [!] %CADDY_CTR% does not exist)
call :log_silent "Resume complete"
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
echo   Log file: %LOGFILE%
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
call :log_silent "Dev panel selection: %PANEL_CHOICE%"

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
call :log_silent "Viewing frontend logs"
%RT% logs -f %FRONTEND_CTR%
goto :dev_panel

:panel_backend_logs
echo.
echo   --- Backend logs (Ctrl+C to return) ---
call :log_silent "Viewing backend logs"
%RT% logs -f %BACKEND_CTR%
goto :dev_panel

:panel_caddy_logs
echo.
echo   --- Caddy logs (Ctrl+C to return) ---
call :log_silent "Viewing caddy logs"
%RT% logs -f %CADDY_CTR%
goto :dev_panel

:panel_restart_frontend
call :log_silent "Restarting frontend..."
echo   Restarting frontend...
%RT% restart %FRONTEND_CTR% >nul 2>&1
call :log_silent "Frontend restarted"
echo   [OK] Frontend restarted.
goto :dev_panel

:panel_restart_backend
call :log_silent "Restarting backend..."
echo   Restarting backend...
%RT% restart %BACKEND_CTR% >nul 2>&1
call :log_silent "Backend restarted"
echo   [OK] Backend restarted.
goto :dev_panel

:panel_rebuild_frontend
call :log_silent "Rebuilding frontend (full rebuild)..."
echo   Rebuilding frontend...
%RT% rm -f %FRONTEND_CTR% >nul 2>&1
call :start_frontend
call :log_silent "Frontend rebuilt and started"
echo   [OK] Frontend rebuilt and started.
goto :dev_panel

:panel_rebuild_backend
call :log_silent "Rebuilding backend (full rebuild)..."
echo   Rebuilding backend...
%RT% rm -f %BACKEND_CTR% >nul 2>&1
call :start_backend
call :log_silent "Backend rebuilt and started"
echo   [OK] Backend rebuilt and started.
goto :dev_panel

:panel_status
echo.
call :log_silent "Checking container status..."
echo   Container status:
%RT% container inspect --format "{{.State.Running}}" %CADDY_CTR% >nul 2>&1
if !errorlevel! equ 0 (echo     * %CADDY_CTR% — running) else (echo     - %CADDY_CTR% — stopped or not created)
%RT% container inspect --format "{{.State.Running}}" %FRONTEND_CTR% >nul 2>&1
if !errorlevel! equ 0 (echo     * %FRONTEND_CTR% — running) else (echo     - %FRONTEND_CTR% — stopped or not created)
%RT% container inspect --format "{{.State.Running}}" %BACKEND_CTR% >nul 2>&1
if !errorlevel! equ 0 (echo     * %BACKEND_CTR% — running) else (echo     - %BACKEND_CTR% — stopped or not created)
goto :dev_panel

:panel_browser
set "URL=http://localhost:%CADDY_PORT%/researchai/"
call :log_silent "Opening browser: %URL%"
echo   Opening %URL% ...
start "" "%URL%"
goto :dev_panel

:panel_exit
call :log_silent "User requested stop all and exit"
call :stop_all
set "KEEP_ALIVE=0"
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
if "%KEEP_ALIVE%" neq "1" goto :eof_done
call :log_silent "Window closing — stopping containers (KEEP_ALIVE mode)..."
call :stop_all

:eof_done
call :log_silent "Script exiting"
call :log_silent "=========================================="
endlocal
exit /b 0
