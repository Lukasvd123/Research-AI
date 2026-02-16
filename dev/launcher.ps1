#Requires -Version 5.1
# ============================================================================
# Research-AI Dev Launcher (PowerShell)
# ============================================================================
#
# PURPOSE:
#   Starts the Research-AI dev stack (frontend, backend, caddy, neo4j, mongo,
#   heartbeat) inside a Podman pod running in WSL. Provides a simple menu to
#   view logs, rebuild, check health, and stop everything.
#
# HOW IT WORKS:
#   1. The .bat file launches this script with UTF-8 encoding.
#   2. Console Virtual Terminal (VT) processing is enabled so WSL output
#      renders correctly (see "CONSOLE SETUP" section below).
#   3. Prerequisites are checked: WSL, Linux distro, make, podman, env.yaml.
#      Each check explains exactly what failed and how to fix it.
#   4. `make dev` is run inside WSL to start the Podman pod.
#   5. A dev panel menu lets you: view logs, rebuild, health check, browser.
#   6. On exit (menu or window close), containers are ALWAYS torn down via
#      `make dev-down`. There is no "keep running" mode.
#
# USAGE:
#   .\launcher.ps1          -> TUI mode (interactive terminal menu)
#   .\launcher.ps1 -GUI     -> WPF GUI mode (launches launcher-gui.ps1)
#
# WSL OUTPUT HANDLING:
#   WSL pipes raw bytes from Linux to Windows, which causes problems:
#   - ANSI escape codes (colors, cursor moves) garble the Windows console
#   - Bare \n line endings cause "staircase" output without VT processing
#   - Container logs are prefixed with hex IDs, not friendly names
#   - JSON structured logs (Caddy) are unreadable without parsing
#
#   This script fixes all of that:
#   - Enables VT processing via Win32 API (fixes bare \n rendering)
#   - Strips ANSI codes before display (Strip-Ansi function)
#   - Maps container IDs to short labels like CDY, FE, BE, etc.
#   - Parses JSON log fields into "LABEL LVL message" format
#
# ============================================================================

param(
    [switch]$GUI  # Pass -GUI to launch the WPF graphical interface instead
)

# ============================================================================
# CONSOLE SETUP
# ============================================================================
# When launched from cmd.exe (via .bat), the console lacks Virtual Terminal
# (VT) processing. Without it, bare \n from WSL causes a "staircase" effect
# where each line shifts right. We enable it via the kernel32 API.
#
# This is non-fatal -- if it fails, output looks messy but still works.
# ============================================================================

try {
    Add-Type -MemberDefinition @'
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@ -Name 'Console' -Namespace 'Win32' -ErrorAction SilentlyContinue

    $hOut = [Win32.Console]::GetStdHandle(-11)          # STD_OUTPUT_HANDLE
    $mode = 0
    [Win32.Console]::GetConsoleMode($hOut, [ref]$mode) | Out-Null
    # 0x0004 = ENABLE_VIRTUAL_TERMINAL_PROCESSING
    [Win32.Console]::SetConsoleMode($hOut, ($mode -bor 0x0004)) | Out-Null
} catch {}

# Force UTF-8 so multi-byte characters from WSL display correctly.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================

$script:Config = @{
    CaddyPort = 8080                                   # Port Caddy listens on
    PodName   = "research-ai-dev"                      # Podman pod name
    ScriptDir = (Split-Path -Parent $PSScriptRoot)     # Project root
    DevDir    = $PSScriptRoot                          # This /dev folder
    LogDir    = $null                                  # Set in Initialize-Logging
    LogFile   = $null                                  # Set in Initialize-Logging
    WslPath   = $null                                  # Set in Ensure-Prerequisites
}

# ============================================================================
# STATE
# ============================================================================

$script:CleanupDone        = $false   # Prevents double-cleanup on exit
$script:IsGuiMode          = $false   # True when running the WPF GUI
$script:LogCallback        = $null    # GUI sets this to receive log lines
$script:HeartbeatTimer     = $null    # Background timer for health monitoring
$script:HeartbeatFailCount = 0        # Consecutive heartbeat check failures
$script:HeartbeatWarning   = $false   # True after 3+ consecutive failures
$script:HealthFrontend     = "unknown"
$script:HealthBackend      = "unknown"
$script:HealthLastCheck    = ""
$script:ContainerIdMap     = @{}      # Hex container ID -> friendly name
$script:PanelMsg           = $null    # One-shot message shown in dev panel

# ============================================================================
# WSL COMMAND EXECUTION
# ============================================================================
# Two helpers for running bash commands in WSL:
#
#   Invoke-WslStream  - Processes output LINE BY LINE as it arrives.
#                       Used for long-running commands (make dev, make watch).
#
#   Invoke-WslCapture - Returns ALL output at once as a string array.
#                       Used for quick queries (is podman installed? container status).
#
# Both use System.Diagnostics.Process directly instead of PowerShell's native
# pipeline to get clean UTF-8 output without encoding transformations.
# ============================================================================

function Invoke-WslStream {
    param(
        [string]$Command,         # Bash command to run inside WSL
        [scriptblock]$OnLine      # Called once per non-empty output line
    )

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName               = "wsl.exe"
    $pinfo.Arguments              = "bash -c ""$Command"""
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError  = $true
    $pinfo.UseShellExecute        = $false
    $pinfo.CreateNoWindow         = $true
    $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    $proc = [System.Diagnostics.Process]::Start($pinfo)

    # ReadLine() blocks until a full line arrives or the stream ends
    while ($null -ne ($line = $proc.StandardOutput.ReadLine())) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            & $OnLine $line
        }
    }

    $proc.WaitForExit()
    return $proc.ExitCode
}

function Invoke-WslCapture {
    param([string]$Command)

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName               = "wsl.exe"
    $pinfo.Arguments              = "bash -c ""$Command"""
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError  = $true
    $pinfo.UseShellExecute        = $false
    $pinfo.CreateNoWindow         = $true
    $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $output = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()

    $script:LastWslExitCode = $proc.ExitCode
    # Split on newlines, drop empty trailing lines
    return ($output -split "`r?`n" | Where-Object { $_ -ne '' })
}

# ============================================================================
# CONTAINER ID RESOLUTION
# ============================================================================
# Podman log lines start with the container's hex ID:
#   a1b2c3d4 INFO: server started
#
# To make this readable, we query `podman ps` to build an ID -> name map,
# then replace IDs with short labels like "FE", "BE", "CDY".
# ============================================================================

function Update-ContainerIdMap {
    $raw = Invoke-WslCapture "podman ps --format '{{.ID}} {{.Names}}' 2>/dev/null"
    if ($script:LastWslExitCode -ne 0) { return }

    foreach ($line in $raw) {
        if ($line -match '^([0-9a-fA-F]+)\s+(.+)$') {
            $id    = $Matches[1].Trim()
            $name  = $Matches[2].Trim()
            $label = $name -replace '^research-ai-dev-', ''
            $script:ContainerIdMap[$id] = $label
        }
    }
}

function Get-ContainerLabel {
    param([string]$Id)

    # Exact match
    if ($script:ContainerIdMap.ContainsKey($Id)) {
        return $script:ContainerIdMap[$Id]
    }
    # Prefix match (podman sometimes uses truncated IDs)
    foreach ($key in $script:ContainerIdMap.Keys) {
        if ($key.StartsWith($Id) -or $Id.StartsWith($key)) {
            return $script:ContainerIdMap[$key]
        }
    }
    # Fallback: first 8 hex chars
    if ($Id.Length -gt 8) { return $Id.Substring(0, 8) }
    return $Id
}

# Fixed-width labels for aligned log output
$script:LabelDisplay = @{
    "caddy"          = "  CDY"
    "frontend"       = "   FE"
    "api"            = "   BE"
    "surf-heartbeat" = "   HB"
    "neo4j"          = "  N4J"
    "mongo"          = "  MDB"
}

function Get-PaddedLabel {
    param([string]$Label)
    if ($script:LabelDisplay.ContainsKey($Label)) {
        return $script:LabelDisplay[$Label]
    }
    return $Label.PadLeft(5).Substring(0, 5)
}

# ============================================================================
# LOG LINE FORMATTING
# ============================================================================
# Raw podman log lines look like:
#   a1b2c3d4 {"level":"info","ts":...,"logger":"http","msg":"handled request"}
#   a1b2c3d4 INFO: Application startup complete
#   a1b2c3d4 08:30:15 - Compiled successfully
#
# Format-LogLine transforms them into aligned, readable output:
#    BE INF  Application startup complete
#    FE INF  Compiled successfully
#   CDY INF  [http] handled request
#
# Steps:
#   1. Strip ANSI escape codes (Strip-Ansi)
#   2. Extract the hex container ID prefix -> look up friendly label
#   3. Detect log level from various formats (plain, JSON, timestamp)
#   4. Return "LABEL LVL  message"
# ============================================================================

function Strip-Ansi {
    param([string]$Text)
    # CSI sequences: ESC[31m (color), ESC[2J (clear screen), ESC[1;1H (cursor)
    $clean = $Text -replace '\x1b\[[0-9;]*[A-Za-z]', ''
    # OSC sequences: ESC]0;title BEL (terminal title changes)
    $clean = $clean -replace '\x1b\][^\x07\x1b]*(\x07|\x1b\\)', ''
    # Remaining bare ESC characters
    $clean = $clean -replace '\x1b', ''
    # Bare CR from progress bars / spinners
    $clean = $clean -replace "`r(?!`n)", ''
    return $clean
}

function Format-LogLine {
    param([string]$RawLine)

    $line = Strip-Ansi $RawLine
    $line = $line -replace '\s+', ' '
    $line = $line.Trim()

    if ([string]::IsNullOrWhiteSpace($line)) { return $null }

    # Does the line start with a hex container ID?
    if ($line -match '^([0-9a-fA-F]{8,64})\s(.*)$') {
        $ctrId   = $Matches[1]
        $content = $Matches[2]
        $label   = Get-ContainerLabel $ctrId
        $padded  = Get-PaddedLabel $label
        $level   = ""

        # Pattern 1: "INFO: message" / "ERROR: message"
        if ($content -match '^(INFO|WARNING|ERROR|DEBUG|CRITICAL):\s+(.*)$') {
            $level   = $Matches[1]
            $content = $Matches[2]
        }
        # Pattern 2: JSON prefix + timestamp like "{...}08:30:15 - message"
        elseif ($content -match '^\{.*?\}(\d{2}:\d{2}:\d{2}\s*-\s*.*)$') {
            $content = $Matches[1]; $level = "INFO"
        }
        # Pattern 3: Plain timestamp "08:30:15 - message"
        elseif ($content -match '^\d{2}:\d{2}:\d{2}\s*-\s*(.*)$') {
            $content = $Matches[1]; $level = "INFO"
        }
        # Pattern 4: JSON structured log with "level" + "msg" (Caddy)
        elseif ($content -match '^\{.+"level"\s*:\s*"([^"]+)".+"msg"\s*:\s*"([^"]*)"') {
            $level  = $Matches[1].ToUpper()
            $msg    = $Matches[2]
            $logger = ""
            if ($content -match '"logger"\s*:\s*"([^"]*)"') { $logger = $Matches[1] }
            $content = if ($logger) { "[$logger] $msg" } else { $msg }
        }

        # 3-character level tag for aligned output
        $levelTag = switch ($level) {
            "INFO"     { "INF" }
            "WARNING"  { "WRN" }
            "WARN"     { "WRN" }
            "ERROR"    { "ERR" }
            "DEBUG"    { "DBG" }
            "CRITICAL" { "FTL" }
            default    { "   " }
        }

        return "$padded $levelTag  $content"
    }

    # No container ID prefix -- indent to align with formatted lines
    return "            $line"
}

function Get-LogLevel {
    param([string]$FormattedLine)
    if ($FormattedLine -match '\sERR\s|\sFTL\s') { return "error" }
    if ($FormattedLine -match '\sWRN\s')          { return "warn" }
    if ($FormattedLine -match '\sDBG\s')          { return "debug" }
    return "info"
}

function Write-FormattedLogLine {
    param([string]$RawLine)

    $formatted = Format-LogLine $RawLine
    if ($null -eq $formatted) { return }

    # Color-code output by severity
    $level = Get-LogLevel $formatted
    switch ($level) {
        "error" { Write-Host "  $formatted" -ForegroundColor Red }
        "warn"  { Write-Host "  $formatted" -ForegroundColor Yellow }
        "debug" { Write-Host "  $formatted" -ForegroundColor DarkGray }
        default { Write-Host "  $formatted" }
    }

    # Append to log file
    $logTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$logTs] $formatted" | Out-File -Append -FilePath $script:Config.LogFile -Encoding utf8 -ErrorAction SilentlyContinue
}

# ============================================================================
# FILE LOGGING
# ============================================================================
# All launcher activity is logged to dev/logs/run_<timestamp>.log for
# debugging when something goes wrong during startup.
# ============================================================================

function Initialize-Logging {
    $script:Config.LogDir = Join-Path $script:Config.DevDir "logs"
    if (-not (Test-Path $script:Config.LogDir)) {
        New-Item -ItemType Directory -Path $script:Config.LogDir -Force | Out-Null
    }
    $ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $script:Config.LogFile = Join-Path $script:Config.LogDir "run_$ts.log"

    Write-Log "=========================================="
    Write-Log "Research-AI Dev Launcher started"
    Write-Log "Working dir: $($script:Config.ScriptDir)"
    Write-Log "Log file:    $($script:Config.LogFile)"
    Write-Log "=========================================="
}

function Write-Log {
    param(
        [string]$Message,
        [switch]$Silent    # Log file only, don't print to console
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if (-not $Silent) {
        Write-Host "  [$ts] $Message"
        if ($script:LogCallback) {
            try { & $script:LogCallback "[$ts] $Message" } catch {}
        }
    }
    "[$ts] $Message" | Out-File -Append -FilePath $script:Config.LogFile -Encoding utf8 -ErrorAction SilentlyContinue
}

# ============================================================================
# PREREQUISITES
# ============================================================================
# Checks WSL, Linux distro, make, podman, and env.yaml before doing anything.
# Each failure gives a clear error with step-by-step fix instructions.
# ============================================================================

function Get-WslPath {
    param([string]$WindowsPath)
    # Convert "C:\Users\foo\project" -> "/mnt/c/Users/foo/project"
    $p = $WindowsPath -replace '\\', '/'
    if ($p -match '^([A-Za-z]):(.*)') {
        return "/mnt/$($Matches[1].ToLower())$($Matches[2])"
    }
    return $p
}

function Ensure-Prerequisites {
    Write-Log "Checking prerequisites..."

    # --- WSL executable ---
    Write-Log "Checking WSL..."
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "  [ERROR] WSL is not installed." -ForegroundColor Red
        Write-Host ""
        Write-Host "  HOW TO FIX:"
        Write-Host "    1. Open PowerShell as Administrator"
        Write-Host "    2. Run: wsl --install"
        Write-Host "    3. Restart your computer"
        Write-Host "    4. Run this launcher again"
        Write-Host ""
        throw "WSL is not installed. Run 'wsl --install' in an admin PowerShell."
    }
    Write-Log "[OK] WSL found"

    # --- Linux distro ---
    Write-Log "Checking WSL Linux distribution..."
    $wslTest = Invoke-WslCapture "echo ok"
    if ($script:LastWslExitCode -ne 0 -or "$wslTest" -notmatch "ok") {
        Write-Host ""
        Write-Host "  [ERROR] No working WSL Linux distribution found." -ForegroundColor Red
        Write-Host ""
        Write-Host "  HOW TO FIX:"
        Write-Host "    1. Open PowerShell as Administrator"
        Write-Host "    2. Run: wsl --install -d Ubuntu"
        Write-Host "    3. Restart your computer"
        Write-Host "    4. Run this launcher again"
        Write-Host ""
        throw "No WSL distribution. Install with: wsl --install -d Ubuntu"
    }
    Write-Log "[OK] WSL distribution available"

    # --- Resolve WSL path ---
    $script:Config.WslPath = Get-WslPath $script:Config.ScriptDir
    Write-Log "WSL path: $($script:Config.WslPath)"

    # --- make ---
    Write-Log "Checking 'make' in WSL..."
    Invoke-WslCapture "command -v make 2>/dev/null" | Out-Null
    if ($script:LastWslExitCode -ne 0) {
        Write-Log "'make' not found, auto-installing..."
        $installOutput = Invoke-WslCapture "sudo apt-get update -qq 2>&1 && sudo apt-get install -y -qq make 2>&1"
        "$installOutput" | Out-File -Append $script:Config.LogFile -ErrorAction SilentlyContinue
        if ($script:LastWslExitCode -ne 0) {
            Write-Host ""
            Write-Host "  [ERROR] Could not install 'make' in WSL." -ForegroundColor Red
            Write-Host ""
            Write-Host "  HOW TO FIX:"
            Write-Host "    1. Open WSL: wsl"
            Write-Host "    2. Run: sudo apt-get update && sudo apt-get install -y make"
            Write-Host "    3. Run this launcher again"
            Write-Host ""
            throw "make is required but could not be installed."
        }
        Write-Log "[OK] make installed"
    } else {
        Write-Log "[OK] make available"
    }

    # --- podman ---
    Write-Log "Checking 'podman' in WSL..."
    Invoke-WslCapture "command -v podman 2>/dev/null" | Out-Null
    if ($script:LastWslExitCode -ne 0) {
        Write-Host ""
        Write-Host "  [ERROR] podman is not installed in WSL." -ForegroundColor Red
        Write-Host ""
        Write-Host "  HOW TO FIX:"
        Write-Host "    1. Open WSL: wsl"
        Write-Host "    2. Run: sudo apt-get update && sudo apt-get install -y podman"
        Write-Host "    3. Run this launcher again"
        Write-Host ""
        throw "podman is not installed in WSL."
    }
    Write-Log "[OK] podman available"

    # --- env.yaml ---
    Write-Log "Checking environment configuration..."
    Setup-EnvYaml

    # Build container ID map for log formatting
    Update-ContainerIdMap
    Write-Log "All prerequisites satisfied."
}

function Setup-EnvYaml {
    $kubeDir    = Join-Path $script:Config.ScriptDir "kube"
    $envYaml    = Join-Path $kubeDir "env.yaml"
    $envExample = Join-Path $kubeDir "env.yaml.example"

    if (-not (Test-Path $envYaml)) {
        if (Test-Path $envExample) {
            Copy-Item $envExample $envYaml
            Write-Log "Created kube/env.yaml from example template"
        } else {
            Write-Host ""
            Write-Host "  [ERROR] kube/env.yaml.example not found." -ForegroundColor Red
            Write-Host "  The repository may be incomplete. Try: git pull"
            Write-Host ""
            throw "kube/env.yaml.example not found."
        }
    }

    # Warn if credentials are still placeholders
    $content = Get-Content $envYaml -Raw
    if ($content -match 'your_username' -or $content -match 'your_password') {
        Write-Log "[!] env.yaml has placeholder credentials"
        Write-Host ""
        Write-Host "  +---------------------------------------------------------+"
        Write-Host "  |  ACTION REQUIRED: Configure your credentials            |"
        Write-Host "  +---------------------------------------------------------+"
        Write-Host ""
        Write-Host "  Edit this file and replace placeholders with real values:"
        Write-Host "    $envYaml"
        Write-Host ""

        if ($script:IsGuiMode) {
            Write-Log "Edit env.yaml before starting: $envYaml"
        } else {
            Read-Host "  Press Enter after you have edited the file"
            $content = Get-Content $envYaml -Raw
            if ($content -match 'your_username' -or $content -match 'your_password') {
                Write-Log "[WARNING] env.yaml still has placeholders - continuing anyway"
            } else {
                Write-Log "[OK] env.yaml configured"
            }
        }
    } else {
        Write-Log "[OK] env.yaml configured"
    }
}

# ============================================================================
# MAKE RUNNER
# ============================================================================
# Runs a Makefile target inside WSL with real-time formatted log output.
# ============================================================================

function Invoke-Make {
    param([string]$Target)

    $wslPath = $script:Config.WslPath
    Write-Host ""
    Write-Log "Running: make $Target"
    Write-Host "  --------------------------------------------------------"

    try {
        $exitCode = Invoke-WslStream -Command "cd '$wslPath' && make $Target 2>&1" -OnLine {
            param($line)
            Write-FormattedLogLine -RawLine $line
        }
    } catch {
        # If the WSL process itself fails to start (e.g., WSL crashed)
        Write-Log "[ERROR] Failed to run WSL command: $_"
        Write-Log "[ERROR] Stack: $($_.ScriptStackTrace)" -Silent
        Write-Host "  [ERROR] WSL command failed: $_" -ForegroundColor Red
        $exitCode = 1
    }

    Write-Host "  --------------------------------------------------------"
    if ($exitCode -ne 0) {
        Write-Log "[ERROR] make $Target failed (exit code $exitCode)"
    } else {
        Write-Log "make $Target completed successfully"
    }
    Write-Host ""
    return $exitCode
}

# ============================================================================
# HEALTH CHECKS
# ============================================================================
# Checks frontend and backend via curl inside WSL (services are only
# accessible from the WSL network). HTTP 2xx/3xx = healthy.
# ============================================================================

function Test-ServiceHealth {
    $port = $script:Config.CaddyPort

    Write-Host "`n  Waiting for services to initialize (5s)..."
    Start-Sleep -Seconds 5
    Write-Host "`n  --- Health Check ---`n"

    # Both checks in one WSL call for speed
    $result = Invoke-WslCapture "echo FE=`$(curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai/' 2>/dev/null); echo BE=`$(curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai-api/health' 2>/dev/null)"

    $feCode = "000"; $beCode = "000"
    foreach ($ln in $result) {
        if ($ln -match '^FE=(\d+)') { $feCode = $Matches[1] }
        if ($ln -match '^BE=(\d+)') { $beCode = $Matches[1] }
    }

    $feOk = "$feCode" -match "^[23]"
    $beOk = "$beCode" -match "^[23]"
    $allOk = $feOk -and $beOk

    $script:HealthFrontend  = if ($feOk) { "OK" } else { "DOWN" }
    $script:HealthBackend   = if ($beOk) { "OK" } else { "DOWN" }
    $script:HealthLastCheck = Get-Date -Format "HH:mm:ss"

    if ($feOk) { Write-Host "    [OK]    Frontend - http://localhost:$port/researchai/" }
    else       { Write-Host "    [FAIL]  Frontend - http://localhost:$port/researchai/  (HTTP $feCode)" -ForegroundColor Red }

    if ($beOk) { Write-Host "    [OK]    Backend  - http://localhost:$port/researchai-api/health" }
    else       { Write-Host "    [FAIL]  Backend  - http://localhost:$port/researchai-api/health  (HTTP $beCode)" -ForegroundColor Red }

    Write-Host ""
    if ($allOk) {
        Write-Host "  All services are healthy!"
    } else {
        Write-Host "  [!] Some checks failed. Services may still be starting." -ForegroundColor Yellow
        Write-Host "      Wait 10-15 seconds and try [H] again."
    }

    Write-Log "Health: FE=$($script:HealthFrontend) BE=$($script:HealthBackend)" -Silent
    return $allOk
}

# ============================================================================
# HEARTBEAT MONITOR
# ============================================================================
# Background timer (every 60s) that checks:
#   - Is the heartbeat container running?
#   - Are frontend/backend endpoints responding?
# Results shown in the dev panel header. Warns after 3 consecutive failures.
# ============================================================================

function Start-HeartbeatMonitor {
    if ($script:HeartbeatTimer) { return }

    $script:HeartbeatFailCount = 0
    $script:HeartbeatWarning   = $false

    $timer = New-Object System.Timers.Timer
    $timer.Interval  = 35000   # First check after 35s, then 60s
    $timer.AutoReset = $true

    Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
        if ($script:HeartbeatTimer -and $script:HeartbeatTimer.Interval -lt 60000) {
            $script:HeartbeatTimer.Interval = 60000
        }

        $port    = 8080
        $ctrName = "research-ai-dev-surf-heartbeat"

        $result = Invoke-WslCapture "echo HB=`$(podman inspect --format '{{.State.Running}}' $ctrName 2>/dev/null || echo false); echo FE=`$(curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai/' 2>/dev/null); echo BE=`$(curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai-api/health' 2>/dev/null)"

        $hbOk = $false; $feCode = "000"; $beCode = "000"
        foreach ($ln in $result) {
            if ($ln -match '^HB=(.+)') { $hbOk = $Matches[1] -match "true" }
            if ($ln -match '^FE=(\d+)') { $feCode = $Matches[1] }
            if ($ln -match '^BE=(\d+)') { $beCode = $Matches[1] }
        }

        if (-not $hbOk) {
            $script:HeartbeatFailCount++
            if ($script:HeartbeatFailCount -ge 3) { $script:HeartbeatWarning = $true }
        } else {
            $script:HeartbeatFailCount = 0
            $script:HeartbeatWarning   = $false
        }

        $script:HealthFrontend  = if ("$feCode" -match "^[23]") { "OK" } else { "DOWN" }
        $script:HealthBackend   = if ("$beCode" -match "^[23]") { "OK" } else { "DOWN" }
        $script:HealthLastCheck = Get-Date -Format "HH:mm:ss"
    } | Out-Null

    $timer.Start()
    $script:HeartbeatTimer = $timer
    Write-Log "Background health monitor started (every 60s)"
}

function Stop-HeartbeatMonitor {
    if ($script:HeartbeatTimer) {
        $script:HeartbeatTimer.Stop()
        $script:HeartbeatTimer.Dispose()
        $script:HeartbeatTimer = $null
        Get-EventSubscriber | Where-Object { $_.SourceObject -is [System.Timers.Timer] } |
            Unregister-Event -ErrorAction SilentlyContinue
    }
}

function Stop-WslHeartbeats {
    Write-Log "Stopping WSL heartbeat processes..."
    Invoke-WslCapture "pkill -f surf-heartbeat 2>/dev/null; true" | Out-Null
}

# ============================================================================
# TUI MENU
# ============================================================================

function Read-MenuChoice {
    param([string]$Title, [string[]]$Options)
    Write-Host ""
    Write-Host "  $Title"
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "    [$($i + 1)] $($Options[$i])"
    }
    Write-Host ""
    do {
        $raw = Read-Host "  Select option"
        $val = $raw -as [int]
    } while ($null -eq $val -or $val -lt 1 -or $val -gt $Options.Count)
    return $val - 1
}

function Show-MainMenu {
    try { Ensure-Prerequisites } catch {
        Write-Log "[ERROR] Prerequisites failed: $_"
        Write-Log "[ERROR] Stack: $($_.ScriptStackTrace)" -Silent
        Write-Host ""
        Write-Host "  [ERROR] Cannot continue - prerequisite check failed." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Error details: $_" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Press Enter to exit..."
        Read-Host | Out-Null
        return
    }

    $choice = Read-MenuChoice -Title "What would you like to do?" -Options @(
        'Start full stack'
        'Stop all containers'
    )

    switch ($choice) {
        0 {
            Write-Log "Starting full stack..."
            $exitCode = Invoke-Make "dev"

            if ($exitCode -ne 0) {
                Write-Host ""
                Write-Host "  [ERROR] 'make dev' failed (exit code $exitCode)" -ForegroundColor Red
                Write-Host ""
                Write-Host "  WHAT TO TRY:"
                Write-Host "    1. Read the error output above"
                Write-Host "    2. Run manually in WSL to see full output:"
                Write-Host "       wsl bash -c 'cd $($script:Config.WslPath) && make dev'"
                Write-Host "    3. Check if ports are in use:"
                Write-Host "       wsl bash -c 'ss -tlnp | grep 8080'"
                Write-Host "    4. Clean up and retry:"
                Write-Host "       wsl bash -c 'cd $($script:Config.WslPath) && make dev-down'"
                Write-Host ""
                Write-Host "  Log file: $($script:Config.LogFile)"
                Write-Host ""
                Read-Host "  Press Enter to exit"
                return
            }

            Update-ContainerIdMap
            Start-HeartbeatMonitor
            Test-ServiceHealth | Out-Null
            Show-DevPanel
        }
        1 {
            Write-Log "Stopping all containers..."
            Invoke-Make "dev-down"
            Write-Log "All containers stopped."
            $script:CleanupDone = $true
        }
    }
}

# -- Dev Panel ---------------------------------------------------------------
# Shown after the stack starts. Only essential actions remain:
#   [1] All logs   [2] Browser   [3] Rebuild   [H] Health   [0] Stop

function Show-DevPanel {
    $cfg = $script:Config

    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "  ======================================================"
        Write-Host "    Research-AI Dev Panel"
        Write-Host "  ======================================================"
        Write-Host ""

        # Status
        $hbStatus = if ($script:HeartbeatWarning) { "WARNING - stopped" } else { "OK" }
        $lastChk  = if ($script:HealthLastCheck) { $script:HealthLastCheck } else { "pending" }

        Write-Host "    Heartbeat:  $hbStatus"
        Write-Host "    Frontend:   $($script:HealthFrontend)"
        Write-Host "    Backend:    $($script:HealthBackend)"
        Write-Host "    Last check: $lastChk  (auto every 60s)"
        Write-Host ""

        if ($script:HeartbeatWarning) {
            Write-Host "  [!] WARNING: Heartbeat has stopped!" -ForegroundColor Red
            Write-Host "      SURF server may shut down. Use [3] Rebuild." -ForegroundColor Red
            Write-Host ""
        }

        if ($script:PanelMsg) {
            Write-Host "  $($script:PanelMsg)"
            Write-Host ""
            $script:PanelMsg = $null
        }

        Write-Host "  URLs:"
        Write-Host "    App:  http://localhost:$($cfg.CaddyPort)/researchai/"
        Write-Host "    API:  http://localhost:$($cfg.CaddyPort)/researchai-api/health"
        Write-Host ""
        Write-Host "  Log: $($cfg.LogFile)"
        Write-Host ""

        Write-Host "  Commands:"
        Write-Host "    [1] View all logs    (Ctrl+C to stop)"
        Write-Host "    [2] Open in browser"
        Write-Host "    [3] Rebuild all"
        Write-Host "    [H] Health check"
        Write-Host "    [0] Stop all and exit"
        Write-Host ""

        $key = Read-Host "  Select"
        Write-Log "Panel: $key" -Silent

        switch ($key.ToUpper()) {
            "1" {
                Write-Host "`n  --- All logs (Ctrl+C to stop, then Enter) ---`n"
                Invoke-Make "watch"
                Write-Host "`n  --- End of log stream ---"
                Read-Host "  Press Enter to return"
            }
            "2" {
                Start-Process "http://localhost:$($cfg.CaddyPort)/researchai/"
                $script:PanelMsg = "[OK] Browser opened."
            }
            "3" {
                Invoke-Make "rebuild"
                Update-ContainerIdMap
                $script:PanelMsg = "[OK] Rebuild complete."
            }
            "H" {
                Write-Host ""
                Test-ServiceHealth | Out-Null
                Read-Host "  Press Enter to return"
            }
            "0" {
                Stop-HeartbeatMonitor
                Stop-WslHeartbeats
                Invoke-Make "dev-down"
                $script:CleanupDone = $true
                return
            }
        }
    }
}

# ============================================================================
# CLEANUP
# ============================================================================
# Always stops containers on exit. No "keep running" option.
# CleanupDone flag prevents double-teardown when user already chose [0].
# ============================================================================

function Invoke-Cleanup {
    if ($script:CleanupDone) { return }
    $script:CleanupDone = $true
    $ErrorActionPreference = 'SilentlyContinue'

    Stop-HeartbeatMonitor
    if ($script:Config.WslPath) {
        Write-Log "Stopping containers..."
        Stop-WslHeartbeats
        Invoke-Make "dev-down"
    }

    Write-Log "Script exiting" -Silent
    $ErrorActionPreference = 'Continue'
}

# ============================================================================
# ENTRY POINT
# ============================================================================

Clear-Host
Write-Host ""
Write-Host "  +======================================+"
Write-Host "  |        Research-AI Dev Launcher       |"
Write-Host "  +======================================+"
Write-Host ""
Initialize-Logging

if ($GUI) {
    $script:IsGuiMode = $true
    $guiScript = Join-Path $PSScriptRoot "launcher-gui.ps1"
    if (Test-Path $guiScript) {
        . $guiScript
    } else {
        Write-Host ""
        Write-Host "  [ERROR] GUI script not found: $guiScript" -ForegroundColor Red
        Write-Host "  Expected: dev\launcher-gui.ps1"
        Write-Host "  Make sure the repository is complete (git pull)."
        Write-Host ""
        Write-Host "  Press Enter to close..."
        Read-Host | Out-Null
        exit 1
    }
} else {
    try {
        Show-MainMenu
    } catch {
        Write-Log "[FATAL] $_"
        Write-Host ""
        Write-Host "  [FATAL] Unexpected error:" -ForegroundColor Red
        Write-Host "  $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Stack trace:" -ForegroundColor DarkGray
        Write-Host "  $($_.ScriptStackTrace)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Check log: $($script:Config.LogFile)"
        Write-Host ""
    } finally {
        Invoke-Cleanup
        Write-Host ""
        if ($script:Config.LogFile) {
            Write-Host "  Log: $($script:Config.LogFile)"
        }
        Write-Host ""
        Write-Host "  Press Enter to close..."
        Read-Host | Out-Null
    }
}
