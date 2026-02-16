:: ============================================================================
:: Research-AI Dev Launcher (Terminal / TUI version)
:: ============================================================================
:: Double-click this file to start the dev environment.
:: It launches a PowerShell script that handles everything.
::
:: WHAT THIS FILE DOES:
::   1. Sets the window title
::   2. Switches the console to UTF-8 (so special characters display right)
::   3. Runs the PowerShell launcher script (dev\launcher.ps1)
::   4. If something went wrong, shows an error with common fixes
:: ============================================================================

:: "@echo off" hides the commands themselves from appearing in the window.
@echo off

:: Set the window title bar text.
title Research-AI Dev Launcher

:: "chcp 65001" switches the console to UTF-8 encoding.
:: ">nul" hides the "Active code page: 65001" output.
chcp 65001 >nul

:: Launch the PowerShell script.
::   -NoProfile        = Don't load the user's PowerShell profile (avoids conflicts)
::   -ExecutionPolicy Bypass = Allow running scripts even if the system blocks them
::   -File "..."       = Path to the script to run
::   "%~dp0"           = The folder where THIS .bat file lives (e.g., C:\project\)
::   %*                = Pass along any extra arguments the user typed
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev\launcher.ps1" %*

:: "%errorlevel%" holds the exit code of the command that just ran.
:: "neq 0" means "not equal to zero" (zero = success, anything else = error).
if %errorlevel% neq 0 (
    echo.
    echo   [ERROR] The launcher exited with error code %errorlevel%.
    echo.
    echo   COMMON CAUSES:
    echo     - PowerShell execution policy is too restrictive
    echo     - The dev\launcher.ps1 file is missing or corrupted
    echo     - WSL is not installed or not working
    echo.
    echo   THINGS TO TRY:
    echo     1. Make sure WSL is installed:  wsl --install
    echo     2. Make sure the script exists: dir "%~dp0dev\launcher.ps1"
    echo     3. Try the GUI version instead: run-dev-gui.bat
    echo.
    :: "pause" waits for the user to press a key before closing the window.
    pause
)
