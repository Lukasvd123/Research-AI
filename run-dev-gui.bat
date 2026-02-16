:: ============================================================================
:: Research-AI Dev Launcher (GUI / Window version)
:: ============================================================================
:: Double-click this file to open the graphical dev launcher window.
:: It runs the same PowerShell script as run-dev.bat, but with a -GUI flag
:: that opens a proper Windows window instead of a text menu.
::
:: If this doesn't work, try run-dev.bat instead (the text version).
:: ============================================================================

:: "@echo off" hides the commands themselves from appearing in the window.
@echo off

:: Set the window title bar text.
title Research-AI Dev Launcher (GUI)

:: "chcp 65001" switches the console to UTF-8 encoding.
:: ">nul" hides the "Active code page: 65001" output.
chcp 65001 >nul

:: Launch the PowerShell script with the -GUI flag.
::   -NoProfile        = Don't load the user's PowerShell profile (avoids conflicts)
::   -ExecutionPolicy Bypass = Allow running scripts even if the system blocks them
::   -File "..."       = Path to the script to run
::   "%~dp0"           = The folder where THIS .bat file lives (e.g., C:\project\)
::   -GUI              = Tells launcher.ps1 to open the graphical window
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev\launcher.ps1" -GUI

:: "%errorlevel%" holds the exit code of the command that just ran.
:: "neq 0" means "not equal to zero" (zero = success, anything else = error).
if %errorlevel% neq 0 (
    echo.
    echo   [ERROR] The GUI launcher exited with error code %errorlevel%.
    echo.
    echo   COMMON CAUSES:
    echo     - PowerShell execution policy is too restrictive
    echo     - The dev\launcher.ps1 or dev\launcher-gui.ps1 file is missing
    echo     - WSL is not installed or not working
    echo.
    echo   THINGS TO TRY:
    echo     1. Try the text version instead: run-dev.bat
    echo     2. Make sure the scripts exist:
    echo        dir "%~dp0dev\launcher.ps1"
    echo        dir "%~dp0dev\launcher-gui.ps1"
    echo.
    :: "pause" waits for the user to press a key before closing the window.
    pause
)
