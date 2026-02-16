# ============================================================================
# Research-AI Dev Launcher - WPF GUI
# ============================================================================
#
# PURPOSE:
#   Graphical (WPF) front-end for the dev launcher. Provides buttons instead
#   of a terminal menu. All shared logic (WSL helpers, log formatting,
#   prerequisites) lives in launcher.ps1 which dot-sources this file.
#
# LAUNCHED VIA:
#   .\launcher.ps1 -GUI   or   run-dev-gui.bat
#
# HOW IT WORKS:
#   1. launcher.ps1 runs prerequisites, then dot-sources this file.
#   2. This file defines the WPF window in XAML and wires up button handlers.
#   3. A DispatcherTimer polls heartbeat + health every 60 seconds.
#   4. On window close, containers are ALWAYS stopped (no "keep running").
#
# DEPENDENCIES:
#   - PresentationFramework, PresentationCore, WindowsBase (built into Windows)
#   - All functions from launcher.ps1 (Invoke-WslCapture, Format-LogLine, etc.)
#
# ============================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ============================================================================
# XAML LAYOUT
# ============================================================================
# Defines the WPF window: status indicators, action buttons, log output, URLs.
# Uses a dark color scheme (Catppuccin Mocha palette).
# ============================================================================

[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Research-AI Dev Launcher"
    Height="650" Width="720"
    WindowStartupLocation="CenterScreen"
    Background="#1e1e2e" Foreground="#cdd6f4">

    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#cdd6f4"/>
            <Setter Property="BorderBrush" Value="#45475a"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Margin" Value="4"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Foreground" Value="#cdd6f4"/>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Title -->
        <TextBlock Grid.Row="0" Text="Research-AI Dev Launcher"
                   FontSize="22" FontWeight="Bold" Margin="0,0,0,8"
                   Foreground="#89b4fa"/>

        <!-- Status indicators (colored dots) -->
        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,12">
            <TextBlock Text="WSL+Podman    " FontWeight="SemiBold"/>
            <Ellipse Name="indHeartbeat" Width="10" Height="10" Fill="#6c7086" Margin="8,0,4,0" VerticalAlignment="Center"/>
            <TextBlock Text="Heartbeat" FontSize="11"/>
            <Ellipse Name="indCaddy" Width="10" Height="10" Fill="#6c7086" Margin="8,0,4,0" VerticalAlignment="Center"/>
            <TextBlock Text="Caddy" FontSize="11"/>
            <Ellipse Name="indFrontend" Width="10" Height="10" Fill="#6c7086" Margin="8,0,4,0" VerticalAlignment="Center"/>
            <TextBlock Text="Frontend" FontSize="11"/>
            <Ellipse Name="indBackend" Width="10" Height="10" Fill="#6c7086" Margin="8,0,4,0" VerticalAlignment="Center"/>
            <TextBlock Text="Backend" FontSize="11"/>
        </StackPanel>

        <!-- Action buttons -->
        <WrapPanel Grid.Row="2" Margin="0,0,0,8">
            <Button Name="btnFullStack" Content="Start Full Stack"/>
            <Button Name="btnStopAll" Content="Stop All"/>
            <Button Name="btnRebuild" Content="Rebuild All" FontSize="11"/>
            <Button Name="btnHealthCheck" Content="Health Check" FontSize="11"/>
            <Button Name="btnBrowser" Content="Open Browser"/>
        </WrapPanel>

        <!-- Log output (colored rich text) -->
        <RichTextBox Grid.Row="3" Name="txtLog"
                     IsReadOnly="True"
                     VerticalScrollBarVisibility="Auto"
                     HorizontalScrollBarVisibility="Auto"
                     FontFamily="Cascadia Mono,Consolas,Courier New"
                     FontSize="12"
                     Background="#11111b"
                     Foreground="#a6adc8"
                     BorderBrush="#45475a"
                     Margin="0,0,0,8">
            <FlowDocument Name="logDoc" PageWidth="5000"/>
        </RichTextBox>

        <!-- URL bar -->
        <StackPanel Grid.Row="4" Orientation="Horizontal">
            <TextBlock Text="App: " FontSize="11" Foreground="#a6adc8"/>
            <TextBlock Name="txtAppUrl" Text="" FontSize="11" Foreground="#89b4fa"
                       Cursor="Hand" TextDecorations="Underline"/>
            <TextBlock Text="   API: " FontSize="11" Foreground="#a6adc8"/>
            <TextBlock Name="txtApiUrl" Text="" FontSize="11" Foreground="#89b4fa"
                       Cursor="Hand" TextDecorations="Underline"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# ============================================================================
# UI ELEMENT BINDING
# ============================================================================
# Find all named elements from the XAML and store them in a lookup table.
# ============================================================================

$ui = @{}
@(
    "txtLog", "logDoc", "txtAppUrl", "txtApiUrl",
    "indHeartbeat", "indCaddy", "indFrontend", "indBackend",
    "btnFullStack", "btnStopAll", "btnBrowser",
    "btnRebuild", "btnHealthCheck"
) | ForEach-Object { $ui[$_] = $window.FindName($_) }

# Set URL labels
$cfg = $script:Config
$ui.txtAppUrl.Text = "http://localhost:$($cfg.CaddyPort)/researchai/"
$ui.txtApiUrl.Text = "http://localhost:$($cfg.CaddyPort)/researchai-api/health"

# ============================================================================
# GUI LOG HELPERS
# ============================================================================
# Append-FormattedLog: Formats a raw WSL log line (strip ANSI, parse JSON,
#   map container IDs) and appends it color-coded to the RichTextBox.
#
# Append-PlainLog: Appends a plain message (for status updates like
#   ">>> Starting full stack...") in a specified color.
#
# Both use Dispatcher.Invoke because WPF UI elements can only be modified
# from the UI thread, but log lines may arrive from background threads.
# ============================================================================

$script:GuiLogColors = @{
    "error" = "#f38ba8"   # Red
    "warn"  = "#f9e2af"   # Yellow
    "debug" = "#6c7086"   # Gray
    "info"  = "#a6adc8"   # Light gray
}

function Append-FormattedLog {
    param([string]$RawText)
    $ui.txtLog.Dispatcher.Invoke([action]{
        $formatted = Format-LogLine $RawText
        if ($null -eq $formatted) { return }

        $level = Get-LogLevel $formatted
        $color = $script:GuiLogColors[$level]
        if (-not $color) { $color = "#a6adc8" }

        $paragraph = New-Object System.Windows.Documents.Paragraph
        $paragraph.Margin = [System.Windows.Thickness]::new(0)
        $paragraph.LineHeight = 1

        $run = New-Object System.Windows.Documents.Run
        $run.Text = $formatted
        $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)

        $paragraph.Inlines.Add($run)
        $ui.logDoc.Blocks.Add($paragraph)
        $ui.txtLog.ScrollToEnd()
    })
    Write-Log $RawText -Silent
}

function Append-PlainLog {
    param([string]$Text, [string]$Color = "#89b4fa")
    $ui.txtLog.Dispatcher.Invoke([action]{
        $paragraph = New-Object System.Windows.Documents.Paragraph
        $paragraph.Margin = [System.Windows.Thickness]::new(0)
        $paragraph.LineHeight = 1

        $run = New-Object System.Windows.Documents.Run
        $run.Text = $Text
        $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)

        $paragraph.Inlines.Add($run)
        $ui.logDoc.Blocks.Add($paragraph)
        $ui.txtLog.ScrollToEnd()
    })
    Write-Log $Text -Silent
}

# ============================================================================
# STATUS INDICATOR HELPERS
# ============================================================================
# Color dots: green=#a6e3a1, red=#f38ba8, grey=#6c7086, yellow=#f9e2af
# ============================================================================

function Set-Indicator {
    param([string]$Name, [string]$Color)
    $el = $ui["ind$Name"]
    if ($el) {
        $el.Dispatcher.Invoke([action]{
            $el.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
        })
    }
}

# Query podman for each container's running state and update the dots
function Update-Indicators {
    $podName = $cfg.PodName
    $result = Invoke-WslCapture "for c in surf-heartbeat caddy frontend api; do r=`$(podman inspect --format '{{.State.Running}}' '$podName-'`$c 2>/dev/null || echo false); echo `$c=`$r; done"

    $states = @{}
    foreach ($ln in $result) {
        if ($ln -match '^(\S+)=(.+)$') {
            $states[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    # Map container names to indicator element names
    $nameMap = @{
        "surf-heartbeat" = "Heartbeat"
        "caddy"          = "Caddy"
        "frontend"       = "Frontend"
        "api"            = "Backend"
    }

    foreach ($key in $nameMap.Keys) {
        if ($states[$key] -match "true") {
            Set-Indicator $nameMap[$key] "#a6e3a1"   # Green
        } else {
            Set-Indicator $nameMap[$key] "#6c7086"   # Gray
        }
    }
}

# ============================================================================
# MAKE RUNNER (GUI version)
# ============================================================================
# Same as Invoke-Make but routes output to the GUI log panel instead of the
# console.
# ============================================================================

function Invoke-MakeGui {
    param([string]$Target)
    $wslPath = $script:Config.WslPath

    try {
        $exitCode = Invoke-WslStream -Command "cd '$wslPath' && make $Target 2>&1" -OnLine {
            param($line)
            Append-FormattedLog $line
        }
    } catch {
        # WSL process failed to start (e.g., WSL crashed, OOM, etc.)
        Write-Log "[ERROR] WSL command failed: $_"
        Write-Log "[ERROR] Stack: $($_.ScriptStackTrace)" -Silent
        Append-PlainLog ">>> ERROR: WSL command failed: $_" -Color "#f38ba8"
        $exitCode = 1
    }

    if ($exitCode -ne 0) {
        Write-Log "[ERROR] make $Target failed (exit code $exitCode)"
        Append-PlainLog ">>> 'make $Target' failed (exit code $exitCode)" -Color "#f38ba8"
        Append-PlainLog ">>> Check the log output above. Common causes:" -Color "#f9e2af"
        Append-PlainLog ">>>   - Port in use, podman not running, missing env vars" -Color "#f9e2af"
    }

    return $exitCode
}

# ============================================================================
# BUTTON HANDLERS
# ============================================================================

$ui.btnFullStack.Add_Click({
    Append-PlainLog ">>> Starting full stack (make dev)..."
    $exitCode = Invoke-MakeGui "dev"
    Start-Sleep -Seconds 3
    Update-ContainerIdMap
    Update-Indicators

    if ($exitCode -ne 0) {
        Append-PlainLog ">>> ERROR: make dev failed (exit code $exitCode)" -Color "#f38ba8"
        Append-PlainLog ">>> Try running 'wsl bash -c ""cd $($script:Config.WslPath) && make dev""' manually to see full output." -Color "#f9e2af"
    } else {
        Append-PlainLog ">>> Full stack started."
    }
})

$ui.btnStopAll.Add_Click({
    Append-PlainLog ">>> Stopping all (make dev-down)..."
    Stop-WslHeartbeats
    Invoke-MakeGui "dev-down"
    Update-Indicators
    Append-PlainLog ">>> All stopped."
})

$ui.btnBrowser.Add_Click({
    $url = "http://localhost:$($cfg.CaddyPort)/researchai/"
    Start-Process $url
    Append-PlainLog ">>> Opened browser: $url"
})

$ui.btnRebuild.Add_Click({
    Append-PlainLog ">>> Rebuilding all (make rebuild)..."
    Invoke-MakeGui "rebuild"
    Update-ContainerIdMap
    Update-Indicators
    Append-PlainLog ">>> Rebuild complete."
})

$ui.btnHealthCheck.Add_Click({
    Append-PlainLog ">>> Running health check..."
    $result = Test-ServiceHealth
    if ($result) {
        Append-PlainLog ">>> All healthy!"
    } else {
        Append-PlainLog ">>> Some checks failed. Services may still be starting." -Color "#f38ba8"
    }
})

# Clickable URL labels
$ui.txtAppUrl.Add_MouseLeftButtonUp({ Start-Process $ui.txtAppUrl.Text })
$ui.txtApiUrl.Add_MouseLeftButtonUp({ Start-Process $ui.txtApiUrl.Text })

# ============================================================================
# HEARTBEAT MONITOR (GUI version)
# ============================================================================
# Uses WPF DispatcherTimer instead of System.Timers.Timer because it fires
# on the UI thread, making it safe to update indicators directly.
# ============================================================================

$guiHeartbeatTimer = New-Object System.Windows.Threading.DispatcherTimer
$guiHeartbeatTimer.Interval = [TimeSpan]::FromSeconds(35)
$guiHeartbeatTimer.Add_Tick({
    # Slow down to 60s after the first tick
    if ($guiHeartbeatTimer.Interval.TotalSeconds -lt 60) {
        $guiHeartbeatTimer.Interval = [TimeSpan]::FromSeconds(60)
    }

    $port    = $cfg.CaddyPort
    $ctrName = "$($cfg.PodName)-surf-heartbeat"

    $result = Invoke-WslCapture "echo HB=`$(podman inspect --format '{{.State.Running}}' $ctrName 2>/dev/null || echo false); echo FE=`$(curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai/' 2>/dev/null); echo BE=`$(curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai-api/health' 2>/dev/null)"

    $hbOk = $false; $feCode = "000"; $beCode = "000"
    foreach ($ln in $result) {
        if ($ln -match '^HB=(.+)') { $hbOk = $Matches[1] -match "true" }
        if ($ln -match '^FE=(\d+)') { $feCode = $Matches[1] }
        if ($ln -match '^BE=(\d+)') { $beCode = $Matches[1] }
    }

    # Heartbeat indicator: green -> yellow (1-2 fails) -> red (3+ fails)
    if (-not $hbOk) {
        $script:HeartbeatFailCount++
        if ($script:HeartbeatFailCount -ge 3) {
            $script:HeartbeatWarning = $true
            Set-Indicator "Heartbeat" "#f38ba8"    # Red
        } else {
            Set-Indicator "Heartbeat" "#f9e2af"    # Yellow
        }
    } else {
        $script:HeartbeatFailCount = 0
        $script:HeartbeatWarning = $false
        Set-Indicator "Heartbeat" "#a6e3a1"        # Green
    }

    $script:HealthFrontend  = if ("$feCode" -match "^[23]") { "OK" } else { "DOWN" }
    $script:HealthBackend   = if ("$beCode" -match "^[23]") { "OK" } else { "DOWN" }
    $script:HealthLastCheck = Get-Date -Format "HH:mm:ss"

    Update-Indicators
})

# ============================================================================
# INITIALIZE AND SHOW WINDOW
# ============================================================================

# Route Write-Log output to the GUI log panel
$script:LogCallback = {
    param([string]$Text)
    $ui.txtLog.Dispatcher.Invoke([action]{
        $paragraph = New-Object System.Windows.Documents.Paragraph
        $paragraph.Margin = [System.Windows.Thickness]::new(0)
        $paragraph.LineHeight = 1

        $run = New-Object System.Windows.Documents.Run
        $run.Text = $Text
        $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#89b4fa")

        $paragraph.Inlines.Add($run)
        $ui.logDoc.Blocks.Add($paragraph)
        $ui.txtLog.ScrollToEnd()
    })
}

# Run prerequisite checks and show results in the log panel
Append-PlainLog "Checking prerequisites..."
try {
    Ensure-Prerequisites
    Append-PlainLog "All prerequisites satisfied - ready to launch."
} catch {
    Append-PlainLog "ERROR: $_" -Color "#f38ba8"
    Append-PlainLog "Fix the issue above and restart the launcher." -Color "#f9e2af"
}

Update-Indicators
$guiHeartbeatTimer.Start()

# ============================================================================
# WINDOW CLOSE HANDLER
# ============================================================================
# Always stops containers when the window closes. No "keep running" option.
# ============================================================================

$window.Add_Closing({
    $guiHeartbeatTimer.Stop()

    if ($script:Config.WslPath) {
        Write-Log "Window closing - stopping containers..."
        Stop-WslHeartbeats
        $wslPath = $script:Config.WslPath
        Invoke-WslCapture "cd '$wslPath' && make dev-down 2>&1" | Out-Null
        Write-Log "Containers stopped."
    }

    Write-Log "Window closed."
})

# Show the window (blocks until closed)
$window.ShowDialog() | Out-Null
