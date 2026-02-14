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
            <CheckBox Name="chkIndefinite" Content="Run indefinitely (survive after close)"
                      Foreground="#cdd6f4" Margin="12,0,0,0" VerticalAlignment="Center"
                      FontFamily="Segoe UI" FontSize="12"/>
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

        <!-- Log output (RichTextBox for colored log lines) -->
        <RichTextBox Grid.Row="4" Name="txtLog"
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
    "txtLog", "logDoc", "txtAppUrl", "txtApiUrl",
    "indHeartbeat", "indCaddy", "indFrontend", "indBackend",
    "btnFullStack", "btnResume", "btnStopAll", "btnBrowser",
    "btnRestartFE", "btnRestartBE", "btnRebuild",
    "btnHealthCheck", "btnWatchBE", "btnWatchFE",
    "chkIndefinite"
) | ForEach-Object { $ui[$_] = $window.FindName($_) }

$cfg = $script:Config
$ui.txtAppUrl.Text = "http://localhost:$($cfg.CaddyPort)/researchai/"
$ui.txtApiUrl.Text = "http://localhost:$($cfg.CaddyPort)/researchai-api/health"

# -- Color map for log levels ------------------------------------------------

$script:GuiLogColors = @{
    "error" = "#f38ba8"
    "warn"  = "#f9e2af"
    "debug" = "#6c7086"
    "info"  = "#a6adc8"
}

# -- GUI helpers -------------------------------------------------------------

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
    $result = Invoke-WslCapture "for c in surf-heartbeat caddy frontend api; do r=`$(podman inspect --format '{{.State.Running}}' '$podName-'`$c 2>/dev/null || echo false); echo `$c=`$r; done"
    $states = @{}
    foreach ($ln in $result) {
        if ($ln -match '^(\S+)=(.+)$') {
            $states[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    $nameMap = @{
        "surf-heartbeat" = "Heartbeat"
        "caddy"          = "Caddy"
        "frontend"       = "Frontend"
        "api"            = "Backend"
    }

    foreach ($key in $nameMap.Keys) {
        $running = $states[$key]
        if ($running -match "true") {
            Set-Indicator $nameMap[$key] "#a6e3a1"
        } else {
            Set-Indicator $nameMap[$key] "#6c7086"
        }
    }
}

function Invoke-MakeGui {
    param([string]$Target)
    $wslPath = $script:Config.WslPath
    $cmd = "cd '$wslPath' && make $Target 2>&1"

    $exitCode = Invoke-WslStream -Command $cmd -OnLine {
        param($line)
        Append-FormattedLog $line
    }

    return $exitCode
}

# -- Button handlers ---------------------------------------------------------

$ui.btnFullStack.Add_Click({
    Append-PlainLog ">>> Starting full stack (make dev)..."
    Invoke-MakeGui "dev"
    Start-Sleep -Seconds 3
    Update-ContainerIdMap
    Update-Indicators
    Append-PlainLog ">>> Full stack started."
})

$ui.btnResume.Add_Click({
    Append-PlainLog ">>> Resuming pod (make resume)..."
    Invoke-MakeGui "resume"
    Start-Sleep -Seconds 2
    Update-ContainerIdMap
    Update-Indicators
    Append-PlainLog ">>> Resume complete."
})

$ui.btnStopAll.Add_Click({
    Append-PlainLog ">>> Stopping all (make down)..."
    Stop-AllWatchers
    Stop-WslHeartbeats
    Invoke-MakeGui "down"
    Update-Indicators
    Append-PlainLog ">>> All stopped."
})

$ui.btnBrowser.Add_Click({
    $url = "http://localhost:$($cfg.CaddyPort)/researchai/"
    Start-Process $url
    Append-PlainLog ">>> Opened browser: $url"
})

$ui.btnRestartFE.Add_Click({
    Invoke-MakeGui "restart-ui"
    Append-PlainLog ">>> Frontend restarted."
    Update-Indicators
})

$ui.btnRestartBE.Add_Click({
    Invoke-MakeGui "restart-api"
    Append-PlainLog ">>> Backend restarted."
    Update-Indicators
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
    if ($result) { Append-PlainLog ">>> All healthy!" }
    else { Append-PlainLog ">>> Some checks failed." -Color "#f38ba8" }
})

$ui.btnWatchBE.Add_Click({
    if ($script:WatcherJobs.ContainsKey("backend")) {
        Stop-FileWatcher -Name "backend"
        $ui.btnWatchBE.Content = "Watch BE: OFF"
        Append-PlainLog ">>> Backend auto-reload disabled."
    } else {
        Start-FileWatcher -Name "backend" `
            -WatchPath (Join-Path $cfg.ScriptDir "backend") `
            -Extensions @("*.py") `
            -MakeTarget "restart-api"
        $ui.btnWatchBE.Content = "Watch BE: ON"
        Append-PlainLog ">>> Backend auto-reload enabled."
    }
})

$ui.btnWatchFE.Add_Click({
    if ($script:WatcherJobs.ContainsKey("frontend")) {
        Stop-FileWatcher -Name "frontend"
        $ui.btnWatchFE.Content = "Watch FE: OFF"
        Append-PlainLog ">>> Frontend auto-reload disabled."
    } else {
        Start-FileWatcher -Name "frontend" `
            -WatchPath (Join-Path $cfg.ScriptDir "frontend") `
            -Extensions @("*.ts", "*.tsx", "*.css", "*.html") `
            -MakeTarget "restart-ui"
        $ui.btnWatchFE.Content = "Watch FE: ON"
        Append-PlainLog ">>> Frontend auto-reload enabled."
    }
})

# clickable URLs
$ui.txtAppUrl.Add_MouseLeftButtonUp({ Start-Process $ui.txtAppUrl.Text })
$ui.txtApiUrl.Add_MouseLeftButtonUp({ Start-Process $ui.txtApiUrl.Text })

# -- Heartbeat monitor (GUI version) ----------------------------------------

$guiHeartbeatTimer = New-Object System.Windows.Threading.DispatcherTimer
$guiHeartbeatTimer.Interval = [TimeSpan]::FromSeconds(35)
$guiHeartbeatTimer.Add_Tick({
    if ($guiHeartbeatTimer.Interval.TotalSeconds -lt 60) {
        $guiHeartbeatTimer.Interval = [TimeSpan]::FromSeconds(60)
    }

    $port = $cfg.CaddyPort
    $ctrName = "$($cfg.PodName)-surf-heartbeat"
    $result = Invoke-WslCapture "echo HB=`$(podman inspect --format '{{.State.Running}}' $ctrName 2>/dev/null || echo false); echo FE=`$(curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai/' 2>/dev/null); echo BE=`$(curl -sf -o /dev/null -w '%{http_code}' 'http://localhost:$port/researchai-api/health' 2>/dev/null)"

    $hbOk = $false; $feCode = "000"; $beCode = "000"
    foreach ($ln in $result) {
        if ($ln -match '^HB=(.+)') { $hbOk = $Matches[1] -match "true" }
        if ($ln -match '^FE=(\d+)') { $feCode = $Matches[1] }
        if ($ln -match '^BE=(\d+)') { $beCode = $Matches[1] }
    }

    if (-not $hbOk) {
        $script:HeartbeatFailCount++
        if ($script:HeartbeatFailCount -ge 3) {
            $script:HeartbeatWarning = $true
            Set-Indicator "Heartbeat" "#f38ba8"
        } else {
            Set-Indicator "Heartbeat" "#f9e2af"
        }
    } else {
        $script:HeartbeatFailCount = 0
        $script:HeartbeatWarning = $false
        Set-Indicator "Heartbeat" "#a6e3a1"
    }

    $feOk = "$feCode" -match "^[23]"
    $beOk = "$beCode" -match "^[23]"
    $script:HealthFrontend  = if ($feOk) { "OK" } else { "DOWN" }
    $script:HealthBackend   = if ($beOk) { "OK" } else { "DOWN" }
    $script:HealthLastCheck = Get-Date -Format "HH:mm:ss"

    Update-Indicators
})

# -- Initialize and show ----------------------------------------------------

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

Append-PlainLog "Checking prerequisites..."
try {
    Ensure-Prerequisites
    Append-PlainLog "All prerequisites satisfied - ready to launch."
} catch {
    Append-PlainLog "ERROR: $_" -Color "#f38ba8"
    Append-PlainLog "Fix the issue above and restart the launcher."
}

Update-Indicators
$guiHeartbeatTimer.Start()

# cleanup on window close
$window.Add_Closing({
    $guiHeartbeatTimer.Stop()
    Stop-AllWatchers
    $isIndefinite = $ui.chkIndefinite.IsChecked
    if (-not $isIndefinite -and $script:Config.WslPath) {
        Write-Log "Stopping containers and heartbeat processes..."
        Stop-WslHeartbeats
        $wslPath = $script:Config.WslPath
        Invoke-WslCapture "cd '$wslPath' && make down 2>&1" | Out-Null
        Write-Log "Containers stopped."
    } elseif ($isIndefinite) {
        Write-Log "Indefinite mode - containers will keep running."
    }
    Write-Log "Window closing."
})

$window.ShowDialog() | Out-Null