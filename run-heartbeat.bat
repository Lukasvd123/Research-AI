:: ============================================================================
:: Research-AI Heartbeat Launcher
:: ============================================================================
:: Starts the heartbeat container that keeps the SURF Research Cloud VM alive.
:: The heartbeat sends periodic pings so SURF doesn't shut the server down.
::
:: This script:
::   1. Checks that WSL and podman are available
::   2. Stops any previous heartbeat container
::   3. Starts a new heartbeat container via `make heartbeat`
::   4. Waits a few seconds and checks if the container is actually running
::   5. If something went wrong, shows the container logs so you can debug
::   6. ALWAYS waits for you to press Enter before closing
:: ============================================================================

:: "@echo off" hides commands from appearing in the window.
@echo off

:: Set the window title bar text.
title Research-AI Heartbeat

:: "chcp 65001" switches the console to UTF-8 encoding.
:: ">nul" hides the "Active code page: 65001" output.
chcp 65001 >nul

:: ============================================================================
:: RESOLVE WSL PATH
:: ============================================================================
:: Windows paths (C:\Users\foo) need to be converted to WSL paths
:: (/mnt/c/Users/foo) so we can run `make` inside WSL.
::
:: "%~dp0" is a CMD built-in that gives us the folder this .bat file lives in.
:: We strip the trailing backslash, extract the drive letter, convert it to
:: lowercase, and build the /mnt/x/... path.
:: ============================================================================

:: Get the folder this .bat file is in (e.g., C:\Users\foo\Research-AI\)
set "WIN_DIR=%~dp0"
:: Remove the trailing backslash
set "WIN_DIR=%WIN_DIR:~0,-1%"

:: Extract the drive letter (e.g., "C" from "C:\Users\foo\Research-AI")
for /f "tokens=1 delims=:" %%d in ("%WIN_DIR%") do set "DRIVE=%%d"

:: Get everything after the "C:" part (e.g., "\Users\foo\Research-AI")
call set "REST=%%WIN_DIR:%DRIVE%:=%%"

:: Convert backslashes to forward slashes
set "REST=%REST:\=/%"

:: Convert drive letter to lowercase (WSL needs lowercase)
call :toLower DRIVE_L %DRIVE%

:: Build the WSL path (e.g., "/mnt/c/Users/foo/Research-AI")
set "WSL_DIR=/mnt/%DRIVE_L%%REST%"

:: ============================================================================
:: MAIN
:: ============================================================================

echo.
echo   +======================================+
echo   ^|   Research-AI Heartbeat Launcher     ^|
echo   +======================================+
echo.
echo   Project path (Windows): %WIN_DIR%
echo   Project path (WSL):     %WSL_DIR%
echo.

:: --- Check 1: Is WSL available? ---
echo   [1/4] Checking WSL...
wsl.exe echo ok >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   [ERROR] WSL is not available. -ForegroundColor Red
    echo.
    echo   HOW TO FIX:
    echo     1. Open PowerShell as Administrator
    echo     2. Run: wsl --install
    echo     3. Restart your computer
    echo.
    goto :done
)
echo         [OK] WSL is available.

:: --- Check 2: Is podman installed? ---
echo   [2/4] Checking podman...
wsl.exe bash -c "command -v podman" >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   [ERROR] podman is not installed in WSL.
    echo.
    echo   HOW TO FIX:
    echo     1. Open WSL: wsl
    echo     2. Run: sudo apt-get update ^&^& sudo apt-get install -y podman
    echo.
    goto :done
)
echo         [OK] podman is available.

:: --- Step 3: Stop any existing heartbeat container ---
echo   [3/4] Stopping previous heartbeat (if running)...
wsl.exe bash -c "podman rm -f research-ai-heartbeat 2>/dev/null; true"
echo         Done.

:: --- Step 4: Start heartbeat ---
echo   [4/4] Starting heartbeat container...
echo.
echo   --------------------------------------------------------
wsl.exe bash -c "cd '%WSL_DIR%' && make heartbeat 2>&1"
set MAKE_EXIT=%errorlevel%
echo   --------------------------------------------------------
echo.

:: Check if `make heartbeat` itself failed
if %MAKE_EXIT% neq 0 (
    echo   [ERROR] 'make heartbeat' failed with exit code %MAKE_EXIT%.
    echo.
    echo   COMMON CAUSES:
    echo     - kube/env.yaml is missing or has placeholder credentials
    echo     - The Makefile is missing or corrupted
    echo     - podman cannot pull the alpine image ^(network issue^)
    echo.
    echo   Check the output above for the specific error.
    echo.
    goto :done
)

:: Wait a moment and check if the container is actually running
echo   Waiting 5 seconds to verify container started...
timeout /t 5 /nobreak >nul

wsl.exe bash -c "podman inspect --format '{{.State.Running}}' research-ai-heartbeat 2>/dev/null" > "%TEMP%\hb_check.txt" 2>&1
set /p HB_STATUS=<"%TEMP%\hb_check.txt"
del "%TEMP%\hb_check.txt" 2>nul

echo   Container status: %HB_STATUS%
echo.

if "%HB_STATUS%"=="true" (
    echo   [OK] Heartbeat is running!
    echo.
    echo   The heartbeat will keep the SURF server alive by sending periodic pings.
    echo.
    echo   USEFUL COMMANDS:
    echo     View logs:   wsl bash -c "podman logs -f research-ai-heartbeat"
    echo     Stop:        wsl bash -c "podman rm -f research-ai-heartbeat"
    echo.
) else (
    echo   [ERROR] Heartbeat container is NOT running.
    echo.
    echo   The container started but crashed immediately. Here are the logs:
    echo.
    echo   --------------------------------------------------------
    wsl.exe bash -c "podman logs research-ai-heartbeat 2>&1"
    echo   --------------------------------------------------------
    echo.
    echo   COMMON CAUSES:
    echo     - kube/env.yaml has wrong credentials (VD_SURF_USER / VD_SURF_PASS)
    echo     - kube/surf-heartbeat.sh has Windows line endings (CRLF instead of LF)
    echo       Fix: wsl bash -c "dos2unix kube/surf-heartbeat.sh"
    echo     - Network connectivity issues inside WSL
    echo.
)

:: ============================================================================
:: Always pause before closing so the user can read the output.
:: ============================================================================
:done
echo.
echo   Press any key to close...
pause >nul

:: Jump past the toLower subroutine
goto :eof

:: ============================================================================
:: HELPER: Convert a single character to lowercase
:: ============================================================================
:: CMD has no built-in lowercase function, so we brute-force it by trying
:: every letter. This is ugly but it's the only way in pure CMD.
:: ============================================================================
:toLower
set "%1=%2"
for %%c in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do (
    call set "%1=%%%1:%%c=%%c%%"
)
exit /b
