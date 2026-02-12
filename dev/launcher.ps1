#Requires -Version 5.1
# ============================================================================
# Research-AI Interactive Dev Launcher (PowerShell)
# ============================================================================
# Usage:
#   .\launcher.ps1          -> TUI mode (interactive terminal menu)
#   .\launcher.ps1 -GUI     -> WPF GUI mode (native Windows window)
# ============================================================================

param(
    [switch]$GUI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Config ------------------------------------------------------------------

$script:Config = @{
    CaddyPort    = 8080
    PodName      = "research-ai-dev"

    # paths - auto-resolved
    ScriptDir    = (Split-Path -Parent $PSScriptRoot)
    DevDir       = $PSScriptRoot
    LogDir       = $null
    LogFile      = $null
    WslPath      = $null
}

# -- State -------------------------------------------------------------------

$script:KeepAlive          = $false
$script:CleanupDone        = $false
$script:WatcherJobs        = @{}
$script:HeartbeatTimer     = $null
$script:IsGuiMode          = $false
$script:LogCallback        = $null   # GUI sets this to push log lines into the TextBox
$script:HeartbeatFailCount = 0
$script:HeartbeatWarning   = $false
$script:HealthFrontend     = "unknown"
$script:HealthBackend      = "unknown"
$script:HealthLastCheck    = ""

# ============================================================================
# LOGGING
# ============================================================================

function Initialize-Logging {
    $script:Config.LogDir = Join-Path $script:Config.ScriptDir "logs"
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
    param([string]$Message, [switch]$Silent)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if (-not $Silent) {
        Write-Host "  [$ts] $Message"
        # In GUI mode, also push to the WPF TextBox via callback
        if ($script:LogCallback) {
            try { & $script:LogCallback "[$ts] $Message" } catch {}
        }
    }
    "[$ts] $Message" | Out-File -Append -FilePath $script:Config.LogFile -Encoding utf8 -ErrorAction SilentlyContinue
}

# ============================================================================
# WSL + MAKE HELPERS
# ============================================================================

function Get-WslPath {
    param([string]$WindowsPath)
    # Convert C:\Users\...\Research-AI -> /mnt/c/Users/.../Research-AI
    $p = $WindowsPath -replace '\\', '/'
    if ($p -match '^([A-Za-z]):(.*)') {
        $drive = $Matches[1].ToLower()
        $rest  = $Matches[2]
        return "/mnt/$drive$rest"
    }
    return $p
}

function Ensure-Prerequisites {
    Write-Log "Checking prerequisites..."

    # 1. Check WSL executable
    Write-Log "Checking WSL..."
    $wslExe = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wslExe) {
        throw "WSL is not installed. Please install WSL first: wsl --install"
    }
    Write-Log "[OK] WSL executable found"

    # 2. Check WSL has a working Linux distribution (Ubuntu)
    Write-Log "Checking for WSL Linux distribution..."
    $wslTest = wsl bash -c "echo ok" 2>$null
    if ($LASTEXITCODE -ne 0 -or "$wslTest" -notmatch "ok") {
        Write-Log "[ERROR] No working WSL Linux distribution found"
        Write-Host ""
        Write-Host "  No working WSL Linux distribution found."
        Write-Host "  Please install Ubuntu for WSL (run as Administrator):"
        Write-Host ""
        Write-Host "    wsl --install -d Ubuntu"
        Write-Host ""
        Write-Host "  Then restart your computer and re-run this launcher."
        Write-Host ""
        throw "No WSL distribution available. Install Ubuntu with: wsl --install -d Ubuntu"
    }
    Write-Log "[OK] WSL Linux distribution is available"

    # Resolve WSL path for the repo
    $script:Config.WslPath = Get-WslPath $script:Config.ScriptDir
    Write-Log "WSL project path: $($script:Config.WslPath)"

    # 3. Check make in WSL (redirect stderr inside bash to avoid PowerShell ErrorRecords)
    Write-Log "Checking for 'make' in WSL..."
    $makeCheck = wsl bash -c "command -v make 2>/dev/null"
    if ($LASTEXITCODE -ne 0) {
        Write-Log "'make' not found in WSL, attempting to install..."
        $installOutput = wsl bash -c "sudo apt-get update -qq 2>&1 && sudo apt-get install -y -qq make 2>&1"
        $installExit = $LASTEXITCODE
        "$installOutput" | Out-File -Append $script:Config.LogFile -ErrorAction SilentlyContinue
        if ($installExit -ne 0) {
            Write-Log "[ERROR] Could not auto-install 'make' in WSL"
            Write-Host ""
            Write-Host "  Could not auto-install 'make' in WSL."
            Write-Host "  Please open WSL and install it manually:"
            Write-Host "    wsl"
            Write-Host "    sudo apt-get update && sudo apt-get install -y make"
            Write-Host ""
            throw "make is required in WSL but could not be auto-installed"
        }
        Write-Log "[OK] make installed in WSL"
    } else {
        Write-Log "[OK] make is available in WSL"
    }

    # 4. Check podman in WSL
    Write-Log "Checking for 'podman' in WSL..."
    $podmanCheck = wsl bash -c "command -v podman 2>/dev/null"
    if ($LASTEXITCODE -ne 0) {
        Write-Log "[ERROR] podman is not installed in WSL"
        Write-Host ""
        Write-Host "  podman is not installed in WSL."
        Write-Host "  Please open WSL and install podman:"
        Write-Host "    wsl"
        Write-Host "    sudo apt-get install podman"
        Write-Host ""
        throw "podman not found in WSL"
    }
    Write-Log "[OK] podman is available in WSL"

    # 5. Check kube/env.yaml
    Write-Log "Checking environment configuration..."
    Setup-EnvYaml

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
            throw "kube/env.yaml.example not found. Repository may be incomplete."
        }
    }

    # Check for placeholder/default values that the user needs to fill in
    $content = Get-Content $envYaml -Raw
    if ($content -match 'your_username' -or $content -match 'your_password') {
        Write-Log "[!] env.yaml contains placeholder credentials"
        Write-Host ""
        Write-Host "  +---------------------------------------------------------+"
        Write-Host "  |  ACTION REQUIRED: Configure your credentials            |"
        Write-Host "  +---------------------------------------------------------+"
        Write-Host ""
        Write-Host "  The environment file still contains placeholder values."
        Write-Host "  Please edit the following file with your credentials:"
        Write-Host ""
        Write-Host "    $envYaml"
        Write-Host ""
        Write-Host "  Replace 'your_username' and 'your_password' with real values."
        Write-Host ""

        if ($script:IsGuiMode) {
            Write-Log "Please edit env.yaml before starting services: $envYaml"
        } else {
            Read-Host "  Press Enter after you have edited the file"

            # Re-read and verify
            $content = Get-Content $envYaml -Raw
            if ($content -match 'your_username' -or $content -match 'your_password') {
                Write-Log "[WARNING] env.yaml still contains placeholder values - continuing anyway"
            } else {
                Write-Log "[OK] env.yaml credentials configured"
            }
        }
    } else {
        Write-Log "[OK] kube/env.yaml is configured ($envYaml)"
    }
}

function Invoke-Make {
    param([string]$Target, [switch]$Stream)
    $wslPath = $script:Config.WslPath
    Write-Host ""
    Write-Log "Running: make $Target"
    Write-Host "  --------------------------------------------------------"
    # Redirect stderr->stdout inside bash so PowerShell only sees plain strings,
    # avoiding ErrorRecords that trigger $ErrorActionPreference = "Stop"
    wsl bash -c "cd '$wslPath' && make $Target 2>&1" 2>$null | ForEach-Object {
        $line = $_
        if ($Stream) {
            # Streaming mode (logs) - show raw for readability
            Write-Host "  $line"
        } else {
            Write-Host "  > $line"
        }
        $logTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$logTs] $line" | Out-File -Append -FilePath $script:Config.LogFile -Encoding utf8 -ErrorAction SilentlyContinue
    }
    Write-Host "  --------------------------------------------------------"
    $exitCode = $LASTEXITCODE
    Write-Host ""
    if ($exitCode -ne 0) {
        Write-Log "[WARN] make $Target exited with code $exitCode"
    } else {
        Write-Log "make $Target completed successfully"
    }
    Write-Host ""
    return $exitCode
}

# ============================================================================
# HEALTH CHECKS
# ============================================================================

function Test-ServiceHealth {
    $cfg = $script:Config
    Write-Host "`n  Waiting for services to initialize (5s)..."
    Start-Sleep -Seconds 5
    Write-Host "`n  --- Health Check ---`n"

    $allOk = $true

    $endpoints = [ordered]@{
        "Frontend (Caddy)" = "http://localhost:$($cfg.CaddyPort)/researchai/"
        "Backend  (Caddy)" = "http://localhost:$($cfg.CaddyPort)/researchai-api/health"
    }

    foreach ($label in $endpoints.Keys) {
        $url = $endpoints[$label]
        # Use curl inside WSL for reliable access to podman containers
        $code = wsl bash -c "curl -sf -o /dev/null -w '%{http_code}' '$url' 2>/dev/null" 2>$null
        if ("$code" -match "^[23]") {
            Write-Host "    [OK]    $label - $url"
        } else {
            Write-Host "    [FAIL]  $label - $url  (HTTP $code)"
            $allOk = $false
        }
    }

    Write-Host ""
    if ($allOk) {
        Write-Host "  All services are healthy!"
    } else {
        Write-Host "  [!] Some checks failed - services may still be starting"
    }
    Write-Log "Health check complete (all_ok=$allOk)" -Silent
    return $allOk
}

# ============================================================================
# HEARTBEAT MONITORING
# ============================================================================

function Start-HeartbeatMonitor {
    if ($script:HeartbeatTimer) { return }

    $script:HeartbeatFailCount = 0
    $script:HeartbeatWarning   = $false

    $timer = New-Object System.Timers.Timer
    $timer.Interval = 60000  # 60 seconds
    $timer.AutoReset = $true

    $action = Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
        # --- Heartbeat check (with grace period) ---
        $ctrName = "research-ai-dev-surf-heartbeat"
        $result = wsl bash -c "podman inspect --format '{{.State.Running}}' $ctrName 2>/dev/null"
        if ($LASTEXITCODE -ne 0 -or $result -notmatch "true") {
            $script:HeartbeatFailCount++
            # Only warn after 3 consecutive failures (= 3 minutes grace)
            if ($script:HeartbeatFailCount -ge 3) {
                $script:HeartbeatWarning = $true
            }
        } else {
            $script:HeartbeatFailCount = 0
            $script:HeartbeatWarning = $false
        }

        # --- Periodic health check (via WSL curl for reliable podman access) ---
        $port = 8080
        $feCode = wsl bash -c "curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai/' 2>/dev/null" 2>$null
        $beCode = wsl bash -c "curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai-api/health' 2>/dev/null" 2>$null
        $script:HealthFrontend  = if ("$feCode" -match "^[23]") { "OK" } else { "DOWN" }
        $script:HealthBackend   = if ("$beCode" -match "^[23]") { "OK" } else { "DOWN" }
        $script:HealthLastCheck = Get-Date -Format "HH:mm:ss"
    }

    $timer.Start()
    $script:HeartbeatTimer = $timer
    Write-Log "Background monitor started (heartbeat + health every 60s)"
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

# ============================================================================
# FILE WATCHERS (auto-reload)
# ============================================================================

function Start-FileWatcher {
    param(
        [string]$Name,
        [string]$WatchPath,
        [string[]]$Extensions,
        [string]$MakeTarget
    )

    $watchers = @()

    foreach ($ext in $Extensions) {
        $fsw = New-Object System.IO.FileSystemWatcher
        $fsw.Path = $WatchPath
        $fsw.Filter = $ext
        $fsw.IncludeSubdirectories = $true
        $fsw.EnableRaisingEvents = $false

        $action = {
            $target  = $Event.MessageData.Target
            $wslPath = $Event.MessageData.WslPath
            $name    = $Event.MessageData.Name
            Write-Host "  [Auto-reload] $name file changed: $($Event.SourceEventArgs.Name)"
            wsl bash -c "cd '$wslPath' && make $target 2>&1" 2>$null | Out-Null
        }

        $msgData = @{
            Target  = $MakeTarget
            WslPath = $script:Config.WslPath
            Name    = $Name
        }

        Register-ObjectEvent -InputObject $fsw -EventName Changed -Action $action -MessageData $msgData | Out-Null
        Register-ObjectEvent -InputObject $fsw -EventName Created -Action $action -MessageData $msgData | Out-Null
        Register-ObjectEvent -InputObject $fsw -EventName Renamed -Action $action -MessageData $msgData | Out-Null

        $fsw.EnableRaisingEvents = $true
        $watchers += $fsw
    }

    $script:WatcherJobs[$Name] = $watchers
    Write-Log "$Name auto-reload enabled (watching: $($Extensions -join ', '))" -Silent
}

function Stop-FileWatcher {
    param([string]$Name)
    if ($script:WatcherJobs.ContainsKey($Name)) {
        foreach ($fsw in $script:WatcherJobs[$Name]) {
            $fsw.EnableRaisingEvents = $false
            $fsw.Dispose()
        }
        $script:WatcherJobs.Remove($Name)
        Get-EventSubscriber | Where-Object { $_.SourceObject -is [System.IO.FileSystemWatcher] } |
            Unregister-Event -ErrorAction SilentlyContinue
        Write-Log "$Name auto-reload disabled" -Silent
    }
}

function Stop-AllWatchers {
    foreach ($name in @($script:WatcherJobs.Keys)) {
        Stop-FileWatcher -Name $name
    }
}

# ============================================================================
# TUI MENUS
# ============================================================================

function Read-MenuChoice {
    param(
        [string]$Title,
        [string[]]$Options
    )
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
        Write-Log "[ERROR] Prerequisite check failed: $_"
        Write-Host ""
        Write-Host "  Press Enter to exit..."
        Read-Host | Out-Null
        return
    }

    Write-Host ""
    $choice = Read-MenuChoice -Title "What would you like to do?" -Options @(
        'Start full stack'
        'Stop all'
        'Resume (restart stopped pod)'
    )

    switch ($choice) {
        0 { # full stack
            $script:KeepAlive = (Show-LifetimeMenu)
            Write-Log "Starting full stack..."
            $exitCode = Invoke-Make "up"
            if ($exitCode -ne 0) {
                Write-Log "[ERROR] 'make up' failed (exit code $exitCode)"
                Write-Host ""
                Write-Host "  Failed to start the stack. Check the output above."
                Write-Host "  Log file: $($script:Config.LogFile)"
                Write-Host ""
                Write-Host "  Press Enter to exit..."
                Read-Host | Out-Null
                return
            }
            Write-Log "Starting heartbeat monitor..."
            Start-HeartbeatMonitor
            Test-ServiceHealth | Out-Null
            Show-DevPanel
        }
        1 { # stop all
            Write-Log "Stopping all containers..."
            Invoke-Make "down"
            Write-Log "All containers stopped."
            $script:CleanupDone = $true
        }
        2 { # resume
            Write-Log "Resuming stopped pod..."
            $exitCode = Invoke-Make "resume"
            if ($exitCode -ne 0) {
                Write-Log "[ERROR] 'make resume' failed (exit code $exitCode)"
                Write-Host ""
                Write-Host "  Failed to resume the pod. Check the output above."
                Write-Host "  Log file: $($script:Config.LogFile)"
                Write-Host ""
                Write-Host "  Press Enter to exit..."
                Read-Host | Out-Null
                return
            }
            Write-Log "Starting heartbeat monitor..."
            Start-HeartbeatMonitor
            Test-ServiceHealth | Out-Null
            Show-DevPanel
        }
    }
}

function Show-LifetimeMenu {
    $choice = Read-MenuChoice -Title "Container lifetime:" -Options @(
        'Keep alive while this window is open'
        'Run indefinitely - survive after script closes'
    )
    return ($choice -eq 0)
}

function Show-DevPanel {
    $cfg = $script:Config

    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "  ======================================================"
        Write-Host "    Dev Panel"
        Write-Host "  ======================================================"
        Write-Host ""

        # --- Status line ---
        $hbStatus = if ($script:HeartbeatWarning) { "WARNING - stopped" } else { "OK" }
        $feStatus = $script:HealthFrontend
        $beStatus = $script:HealthBackend
        $lastChk  = if ($script:HealthLastCheck) { $script:HealthLastCheck } else { "pending" }

        Write-Host "  Status:"
        Write-Host "    Heartbeat:  $hbStatus"
        Write-Host "    Frontend:   $feStatus"
        Write-Host "    Backend:    $beStatus"
        Write-Host "    Last check: $lastChk  (auto-refresh every 60s)"
        Write-Host ""

        if ($script:HeartbeatWarning) {
            Write-Host "  [!] WARNING: Heartbeat container has stopped!"
            Write-Host "      The SURF server may shut down."
            Write-Host "      Use [7] Rebuild to restart everything."
            Write-Host ""
        }

        if ($script:PanelMsg) {
            Write-Host "  $($script:PanelMsg)"
            Write-Host ""
            $script:PanelMsg = $null
        }

        # --- URLs ---
        Write-Host "  Access URLs:"
        Write-Host "    App:  http://localhost:$($cfg.CaddyPort)/researchai/"
        Write-Host "    API:  http://localhost:$($cfg.CaddyPort)/researchai-api/health"
        Write-Host ""
        Write-Host "  Log file: $($cfg.LogFile)"
        Write-Host ""

        # --- Commands ---
        Write-Host "  Commands:"
        Write-Host "    [1] All logs              [5] Restart backend"
        Write-Host "    [2] Backend logs           [6] Restart frontend"
        Write-Host "    [3] Frontend logs          [7] Rebuild (full)"
        Write-Host "    [4] Caddy logs             [8] Status"
        Write-Host "                               [9] Open in browser"
        Write-Host ""

        $beWatch = if ($script:WatcherJobs.ContainsKey("backend")) { "ON" } else { "OFF" }
        $feWatch = if ($script:WatcherJobs.ContainsKey("frontend")) { "ON" } else { "OFF" }
        Write-Host "    [A] Auto-reload backend [$beWatch]"
        Write-Host "    [F] Auto-reload frontend [$feWatch]"
        Write-Host ""
        Write-Host "    [H] Run health check now"
        Write-Host "    [0] Stop all and exit"
        Write-Host ""

        $key = Read-Host "  Select option"
        Write-Log "Dev panel selection: $key" -Silent

        switch ($key.ToUpper()) {
            "1" {
                Write-Host "`n  --- All logs (Ctrl+C to stop, then press Enter) ---`n"
                Invoke-Make "watch" -Stream
                Write-Host ""
                Write-Host "  --- End of log stream ---"
                Read-Host "  Press Enter to return to menu"
            }
            "2" {
                Write-Host "`n  --- Backend logs (Ctrl+C to stop, then press Enter) ---`n"
                Invoke-Make "logs-api" -Stream
                Write-Host ""
                Write-Host "  --- End of log stream ---"
                Read-Host "  Press Enter to return to menu"
            }
            "3" {
                Write-Host "`n  --- Frontend logs (Ctrl+C to stop, then press Enter) ---`n"
                Invoke-Make "logs-ui" -Stream
                Write-Host ""
                Write-Host "  --- End of log stream ---"
                Read-Host "  Press Enter to return to menu"
            }
            "4" {
                Write-Host "`n  --- Caddy logs (Ctrl+C to stop, then press Enter) ---`n"
                Invoke-Make "logs-caddy" -Stream
                Write-Host ""
                Write-Host "  --- End of log stream ---"
                Read-Host "  Press Enter to return to menu"
            }
            "5" {
                Invoke-Make "restart-api"
                $script:PanelMsg = "[OK] Backend restarted."
            }
            "6" {
                Invoke-Make "restart-ui"
                $script:PanelMsg = "[OK] Frontend restarted."
            }
            "7" {
                Invoke-Make "rebuild"
                $script:PanelMsg = "[OK] Full rebuild complete."
            }
            "8" {
                Write-Host ""
                Invoke-Make "status"
                Read-Host "  Press Enter to return to menu"
            }
            "9" {
                $url = "http://localhost:$($cfg.CaddyPort)/researchai/"
                Start-Process $url
                $script:PanelMsg = "[OK] Browser opened."
            }
            "H" {
                Write-Host ""
                Test-ServiceHealth | Out-Null
                Read-Host "  Press Enter to return to menu"
            }
            "A" {
                if ($script:WatcherJobs.ContainsKey("backend")) {
                    Stop-FileWatcher -Name "backend"
                    $script:PanelMsg = "[OK] Auto-reload: Backend disabled"
                } else {
                    Start-FileWatcher -Name "backend" `
                        -WatchPath (Join-Path $cfg.ScriptDir "backend") `
                        -Extensions @("*.py") `
                        -MakeTarget "restart-api"
                    $script:PanelMsg = "[OK] Auto-reload: Backend enabled (*.py)"
                }
            }
            "F" {
                if ($script:WatcherJobs.ContainsKey("frontend")) {
                    Stop-FileWatcher -Name "frontend"
                    $script:PanelMsg = "[OK] Auto-reload: Frontend disabled"
                } else {
                    Start-FileWatcher -Name "frontend" `
                        -WatchPath (Join-Path $cfg.ScriptDir "frontend") `
                        -Extensions @("*.ts", "*.tsx", "*.css", "*.html") `
                        -MakeTarget "restart-ui"
                    $script:PanelMsg = "[OK] Auto-reload: Frontend enabled (ts/tsx/css/html)"
                }
            }
            "0" {
                Stop-AllWatchers
                Stop-HeartbeatMonitor
                Invoke-Make "down"
                $script:CleanupDone = $true
                return
            }
        }
    }
}

# ============================================================================
# CLEANUP ON EXIT
# ============================================================================

function Invoke-Cleanup {
    if ($script:CleanupDone) { return }
    $script:CleanupDone = $true
    $ErrorActionPreference = 'SilentlyContinue'
    Stop-AllWatchers
    Stop-HeartbeatMonitor
    if ($script:KeepAlive -and $script:Config.WslPath) {
        Write-Log "Cleaning up containers (KeepAlive mode)..."
        Invoke-Make "down"
    }
    Write-Log "Script exiting" -Silent
    Write-Log "==========================================" -Silent
    $ErrorActionPreference = 'Continue'
}

# ============================================================================
# ENTRY POINT
# ============================================================================

$script:PanelMsg = $null
Clear-Host
Write-Host ""
Write-Host "  +======================================+"
Write-Host "  |        Research-AI Dev Launcher       |"
Write-Host "  +======================================+"
Write-Host ""
Initialize-Logging

if ($GUI) {
    $script:IsGuiMode = $true
    # launch the GUI version
    $guiScript = Join-Path $PSScriptRoot "launcher-gui.ps1"
    if (Test-Path $guiScript) {
        . $guiScript
    } else {
        Write-Host "  [ERROR] GUI script not found: $guiScript"
        exit 1
    }
} else {
    try {
        Show-MainMenu
    } catch {
        Write-Log "[FATAL] Unhandled error: $_"
    } finally {
        Invoke-Cleanup
        Write-Host ""
        Write-Host "  Log file: $($script:Config.LogFile)"
        Write-Host ""
        Write-Host "  Press Enter to close..."
        Read-Host | Out-Null
    }
}
