# ============================================================================
# Research-AI Dev Launcher - WPF GUI
# ============================================================================
# Launched via: .\launcher.ps1 -GUI   or   run-dev-gui.bat
# Uses WPF (built into Windows) - no external dependencies.
# ============================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# -- XAML Layout -------------------------------------------------------------

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
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Title -->
        <TextBlock Grid.Row="0" Text="Research-AI Dev Launcher"
                   FontSize="22" FontWeight="Bold" Margin="0,0,0,8"
                   Foreground="#89b4fa"/>

        <!-- Status indicators -->
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

        <!-- Launch buttons -->
        <WrapPanel Grid.Row="2" Margin="0,0,0,8">
            <Button Name="btnFullStack" Content="Full Stack"/>
            <Button Name="btnResume" Content="Resume"/>
            <Button Name="btnStopAll" Content="Stop All" />
            <Button Name="btnBrowser" Content="Open Browser"/>
        </WrapPanel>

        <!-- Action buttons -->
        <WrapPanel Grid.Row="3" Margin="0,0,0,8">
            <Button Name="btnRestartFE" Content="Restart FE" FontSize="11"/>
            <Button Name="btnRestartBE" Content="Restart BE" FontSize="11"/>
            <Button Name="btnRebuild" Content="Rebuild All" FontSize="11"/>
            <Button Name="btnHealthCheck" Content="Health Check" FontSize="11"/>
            <Button Name="btnWatchBE" Content="Watch BE: OFF" FontSize="11"/>
            <Button Name="btnWatchFE" Content="Watch FE: OFF" FontSize="11"/>
        </WrapPanel>

        <!-- Log output -->
        <TextBox Grid.Row="4" Name="txtLog"
                 IsReadOnly="True"
                 VerticalScrollBarVisibility="Auto"
                 HorizontalScrollBarVisibility="Auto"
                 FontFamily="Cascadia Mono,Consolas,Courier New"
                 FontSize="12"
                 Background="#11111b"
                 Foreground="#a6adc8"
                 BorderBrush="#45475a"
                 TextWrapping="Wrap"
                 Margin="0,0,0,8"/>

        <!-- URLs bar -->
        <StackPanel Grid.Row="5" Orientation="Horizontal">
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

# -- Bind UI Elements --------------------------------------------------------

$ui = @{}
@(
    "txtLog", "txtAppUrl", "txtApiUrl",
    "indHeartbeat", "indCaddy", "indFrontend", "indBackend",
    "btnFullStack", "btnResume", "btnStopAll", "btnBrowser",
    "btnRestartFE", "btnRestartBE", "btnRebuild",
    "btnHealthCheck", "btnWatchBE", "btnWatchFE"
) | ForEach-Object { $ui[$_] = $window.FindName($_) }

$cfg = $script:Config
$ui.txtAppUrl.Text = "http://localhost:$($cfg.CaddyPort)/researchai/"
$ui.txtApiUrl.Text = "http://localhost:$($cfg.CaddyPort)/researchai-api/health"

# -- GUI helpers -------------------------------------------------------------

function Append-Log {
    param([string]$Text)
    $ui.txtLog.Dispatcher.Invoke([action]{
        $ui.txtLog.AppendText("$Text`r`n")
        $ui.txtLog.ScrollToEnd()
    })
    Write-Log $Text -Silent
}

function Set-Indicator {
    param([string]$Name, [string]$Color)
    $el = $ui["ind$Name"]
    if ($el) {
        $el.Dispatcher.Invoke([action]{
            $el.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
        })
    }
}

function Set-ButtonsEnabled {
    param([bool]$Enabled)
    foreach ($key in $ui.Keys) {
        if ($key -like "btn*") {
            $ui[$key].IsEnabled = $Enabled
        }
    }
}

# green=#a6e3a1, red=#f38ba8, grey=#6c7086, yellow=#f9e2af
function Update-Indicators {
    $podName = $cfg.PodName
    $containers = @{
        Heartbeat = "$podName-surf-heartbeat"
        Caddy     = "$podName-caddy"
        Frontend  = "$podName-frontend"
        Backend   = "$podName-api"
    }
    foreach ($name in $containers.Keys) {
        $ctr = $containers[$name]
        $running = wsl bash -c "podman inspect --format '{{.State.Running}}' $ctr 2>/dev/null"
        if ($LASTEXITCODE -eq 0 -and $running -match "true") {
            Set-Indicator $name "#a6e3a1"
        } else {
            Set-Indicator $name "#6c7086"
        }
    }
}

function Invoke-MakeGui {
    param([string]$Target)
    $wslPath = $script:Config.WslPath
    # Redirect stderr→stdout inside bash to avoid PowerShell ErrorRecords
    $output = wsl bash -c "cd '$wslPath' && make $Target 2>&1"
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Append-Log "$line"
    }
    return $exitCode
}

# -- Button handlers ---------------------------------------------------------

$ui.btnFullStack.Add_Click({
    Append-Log "Starting full stack (make up)..."
    Invoke-MakeGui "up"
    Start-Sleep -Seconds 3
    Update-Indicators
    Append-Log "Full stack started."
})

$ui.btnResume.Add_Click({
    Append-Log "Resuming pod (make resume)..."
    Invoke-MakeGui "resume"
    Start-Sleep -Seconds 2
    Update-Indicators
    Append-Log "Resume complete."
})

$ui.btnStopAll.Add_Click({
    Append-Log "Stopping all (make down)..."
    Stop-AllWatchers
    Invoke-MakeGui "down"
    Update-Indicators
    Append-Log "All stopped."
})

$ui.btnBrowser.Add_Click({
    $url = "http://localhost:$($cfg.CaddyPort)/researchai/"
    Start-Process $url
    Append-Log "Opened browser: $url"
})

$ui.btnRestartFE.Add_Click({
    Invoke-MakeGui "restart-ui"
    Append-Log "Frontend restarted."
    Update-Indicators
})

$ui.btnRestartBE.Add_Click({
    Invoke-MakeGui "restart-api"
    Append-Log "Backend restarted."
    Update-Indicators
})

$ui.btnRebuild.Add_Click({
    Append-Log "Rebuilding all (make rebuild)..."
    Invoke-MakeGui "rebuild"
    Update-Indicators
    Append-Log "Rebuild complete."
})

$ui.btnHealthCheck.Add_Click({
    Append-Log "Running health check..."
    $result = Test-ServiceHealth
    if ($result) { Append-Log "All healthy!" }
    else { Append-Log "Some checks failed." }
})

$ui.btnWatchBE.Add_Click({
    if ($script:WatcherJobs.ContainsKey("backend")) {
        Stop-FileWatcher -Name "backend"
        $ui.btnWatchBE.Content = "Watch BE: OFF"
        Append-Log "Backend auto-reload disabled."
    } else {
        Start-FileWatcher -Name "backend" `
            -WatchPath (Join-Path $cfg.ScriptDir "backend") `
            -Extensions @("*.py") `
            -MakeTarget "restart-api"
        $ui.btnWatchBE.Content = "Watch BE: ON"
        Append-Log "Backend auto-reload enabled."
    }
})

$ui.btnWatchFE.Add_Click({
    if ($script:WatcherJobs.ContainsKey("frontend")) {
        Stop-FileWatcher -Name "frontend"
        $ui.btnWatchFE.Content = "Watch FE: OFF"
        Append-Log "Frontend auto-reload disabled."
    } else {
        Start-FileWatcher -Name "frontend" `
            -WatchPath (Join-Path $cfg.ScriptDir "frontend") `
            -Extensions @("*.ts", "*.tsx", "*.css", "*.html") `
            -MakeTarget "restart-ui"
        $ui.btnWatchFE.Content = "Watch FE: ON"
        Append-Log "Frontend auto-reload enabled."
    }
})

# clickable URLs
$ui.txtAppUrl.Add_MouseLeftButtonUp({ Start-Process $ui.txtAppUrl.Text })
$ui.txtApiUrl.Add_MouseLeftButtonUp({ Start-Process $ui.txtApiUrl.Text })

# -- Heartbeat monitor (GUI version) ----------------------------------------

$guiHeartbeatTimer = New-Object System.Windows.Threading.DispatcherTimer
$guiHeartbeatTimer.Interval = [TimeSpan]::FromSeconds(60)
$guiHeartbeatTimer.Add_Tick({
    # --- Heartbeat check (with grace period, no auto-kill) ---
    $ctrName = "$($cfg.PodName)-surf-heartbeat"
    $result = wsl bash -c "podman inspect --format '{{.State.Running}}' $ctrName 2>/dev/null"
    if ($LASTEXITCODE -ne 0 -or $result -notmatch "true") {
        $script:HeartbeatFailCount++
        if ($script:HeartbeatFailCount -ge 3) {
            $script:HeartbeatWarning = $true
            Set-Indicator "Heartbeat" "#f38ba8"
        } else {
            Set-Indicator "Heartbeat" "#f9e2af"  # yellow = starting/unstable
        }
    } else {
        $script:HeartbeatFailCount = 0
        $script:HeartbeatWarning = $false
        Set-Indicator "Heartbeat" "#a6e3a1"
    }

    # --- Periodic health check (via WSL curl for reliable podman access) ---
    $port = $cfg.CaddyPort
    $feCode = wsl bash -c "curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai/' 2>/dev/null" 2>$null
    $beCode = wsl bash -c "curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai-api/health' 2>/dev/null" 2>$null
    $script:HealthFrontend  = if ("$feCode" -match "^[23]") { "OK" } else { "DOWN" }
    $script:HealthBackend   = if ("$beCode" -match "^[23]") { "OK" } else { "DOWN" }
    $script:HealthLastCheck = Get-Date -Format "HH:mm:ss"

    Update-Indicators
})

# -- Initialize and show ----------------------------------------------------

# Wire up the log callback so Write-Log calls from shared functions
# (like Ensure-Prerequisites) also appear in the GUI TextBox
$script:LogCallback = {
    param([string]$Text)
    $ui.txtLog.Dispatcher.Invoke([action]{
        $ui.txtLog.AppendText("$Text`r`n")
        $ui.txtLog.ScrollToEnd()
    })
}

Append-Log "Checking prerequisites..."
try {
    Ensure-Prerequisites
    Append-Log "All prerequisites satisfied - ready to launch."
} catch {
    Append-Log "ERROR: $_"
    Append-Log "Fix the issue above and restart the launcher."
}

Update-Indicators
$guiHeartbeatTimer.Start()

# cleanup on window close
$window.Add_Closing({
    $guiHeartbeatTimer.Stop()
    Stop-AllWatchers
    Append-Log "Window closing."
})

$window.ShowDialog() | Out-Null
