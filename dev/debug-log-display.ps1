#Requires -Version 5.1
# ============================================================================
# Debug: Why live logs display at wrong horizontal positions in CMD/PowerShell
# ============================================================================
# Captures raw bytes from WSL pipeline, identifies control chars, encoding
# issues, and ANSI sequences that break console layout.
#
# Usage:
#   .\debug-log-display.ps1                      # interactive target pick
#   .\debug-log-display.ps1 -Target watch        # specific target
#   .\debug-log-display.ps1 -MaxLines 100        # capture more
#   .\debug-log-display.ps1 -Live                # wait for NEW lines only
# ============================================================================

param(
    [string]$Target,        # make target: logs-caddy, logs-api, logs-ui, watch, status
    [int]$MaxLines = 40,    # pipeline objects to capture
    [switch]$NoPause        # skip "press Enter" at end
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSScriptRoot
$devDir    = $PSScriptRoot

# ── WSL path ────────────────────────────────────────────────────────────────
$p = $scriptDir -replace '\\', '/'
if ($p -match '^([A-Za-z]):(.*)') {
    $wslPath = "/mnt/$($Matches[1].ToLower())$($Matches[2])"
} else {
    $wslPath = $p
}

# ── Output file ─────────────────────────────────────────────────────────────
$logDir = Join-Path $devDir "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$ts      = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$outFile = Join-Path $logDir "debug-display_$ts.txt"

function Out-Both {
    param([string]$Text)
    $Text | Out-File -Append -FilePath $outFile -Encoding utf8
    Write-Host $Text
}

# ── Helpers ─────────────────────────────────────────────────────────────────

function Get-HexDump {
    param([string]$Str, [int]$Max = 160)
    if (-not $Str -or $Str.Length -eq 0) { return "(empty)" }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Str)
    $count = [Math]::Min($Max, $bytes.Length)
    $hex   = ($bytes[0..($count - 1)] | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    $ascii = -join ($bytes[0..($count - 1)] | ForEach-Object {
        if ($_ -ge 0x20 -and $_ -le 0x7E) { [char]$_ } else { '.' }
    })
    $trunc = if ($bytes.Length -gt $Max) { " ... (+$($bytes.Length - $Max) bytes)" } else { "" }
    return "HEX[$count]: $hex$trunc`n    ASCII:  $ascii"
}

function Get-ControlChars {
    param([string]$Str)
    if (-not $Str) { return "N/A" }
    $found = [ordered]@{}
    for ($i = 0; $i -lt $Str.Length; $i++) {
        $c = [int][char]$Str[$i]
        $tag = switch ($c) {
            0x00 { "NUL" }
            0x07 { "BEL" }
            0x08 { "BS" }
            0x09 { "TAB" }
            0x0A { "LF" }
            0x0B { "VT" }
            0x0C { "FF" }
            0x0D { "CR" }
            0x1B { "ESC" }
            default { if ($c -lt 0x20) { "0x$("{0:X2}" -f $c)" } else { $null } }
        }
        if ($tag) {
            if ($found.Contains($tag)) { $found[$tag] += ", $i" }
            else                       { $found[$tag] = "pos $i" }
        }
    }
    if ($found.Count -eq 0) { return "(none)" }
    return ($found.GetEnumerator() | ForEach-Object { "$($_.Key) @ $($_.Value)" }) -join " | "
}

function Get-AnsiReport {
    param([string]$Str)
    if (-not $Str -or $Str -notmatch '\x1b') { return $null }
    $results = @()
    $csi = [regex]'\x1b\[([0-9;]*)([A-Za-z])'
    foreach ($m in $csi.Matches($Str)) {
        $p = $m.Groups[1].Value; $f = $m.Groups[2].Value
        $desc = switch ($f) {
            'A' { "CursorUP($p)" }
            'B' { "CursorDOWN($p)" }
            'C' { "CursorFWD($p)" }
            'D' { "CursorBACK($p)" }
            'G' { "CursorCOL($p)" }
            'H' { "CursorPOS($p)" }
            'J' { "EraseDisplay($p)" }
            'K' { "EraseLine($p)" }
            'm' { "Color($p)" }
            default { "CSI($p$f)" }
        }
        $results += $desc
    }
    $osc = [regex]'\x1b\]([^\x07\x1b]{0,60})(\x07|\x1b\\)'
    foreach ($m in $osc.Matches($Str)) { $results += "OSC($($m.Groups[1].Value))" }
    return $results -join ", "
}

function Get-LineFlags {
    param([string]$Raw)
    $flags = @()
    if ($Raw -match "`r" -and $Raw -notmatch "`r`n") { $flags += "BARE_CR" }
    $crAll = ([regex]::Matches($Raw, "`r")).Count
    $crLF  = ([regex]::Matches($Raw, "`r`n")).Count
    if ($crAll -gt $crLF)        { $flags += "MIXED_CR($crAll cr, $crLF crlf)" }
    if ($Raw -match "`n")        { $flags += "EMBEDDED_LF" }
    if ($Raw -match '\x1b\[\d*[ABCDGH]') { $flags += "CURSOR_MOVE" }
    if ($Raw -match '\x1b\[\d*G')        { $flags += "CURSOR_COL(!)" }
    if ($Raw -match '\x1b\[\d*C')        { $flags += "CURSOR_FWD(!)" }
    if ($Raw -match '[^\r]\r[^\n]')      { $flags += "CR_OVERWRITE" }
    if ($Raw.Length -gt 200)              { $flags += "LONG($($Raw.Length))" }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Raw)
    if ($bytes | Where-Object { $_ -gt 127 }) { $flags += "NON_ASCII" }

    return $flags
}

# ============================================================================
# MAIN
# ============================================================================

Clear-Host
Write-Host ""
Write-Host "  ================================================"
Write-Host "  Debug: Live Log Display Issues"
Write-Host "  ================================================"
Write-Host "  Output file: $outFile"
Write-Host ""

# ── Environment snapshot ────────────────────────────────────────────────────
$cpOut = try { [Console]::OutputEncoding.CodePage } catch { "?" }
$cpIn  = try { [Console]::InputEncoding.CodePage } catch { "?" }
$conW  = try { [Console]::WindowWidth } catch { "?" }
$conH  = try { [Console]::WindowHeight } catch { "?" }
$term  = try { (wsl bash -c 'echo $TERM' 2>$null).Trim() } catch { "?" }

Out-Both "ENVIRONMENT"
Out-Both "  PS version:     $($PSVersionTable.PSVersion)"
Out-Both "  Host:           $($Host.Name)"
Out-Both "  OutputEncoding: CP $cpOut"
Out-Both "  InputEncoding:  CP $cpIn"
Out-Both "  Console:        ${conW}x${conH}"
Out-Both "  WSL TERM:       $term"
Out-Both "  WSL path:       $wslPath"
Out-Both ""

# ── Encoding warnings ──────────────────────────────────────────────────────
$issues = @()
if ($cpOut -ne 65001 -and $cpOut -ne "?") {
    $issues += "[!!] OutputEncoding is CP $cpOut (NOT UTF-8). Multi-byte chars will garble display."
}
if ($term -ne "dumb" -and $term -ne "?" -and $term -ne "") {
    $issues += "[!!] WSL TERM=$term. Programs may emit ANSI cursor/color codes."
    $issues += "     Set TERM=dumb in the wsl command to suppress them."
}
foreach ($iss in $issues) { Out-Both $iss }
if ($issues.Count -gt 0) { Out-Both "" }

# ── Pod check ───────────────────────────────────────────────────────────────
$podStatus = try { (wsl bash -c "podman pod ps --format '{{.Name}} {{.Status}}' 2>&1").Trim() } catch { "" }
Out-Both "Pod status: $podStatus"
if ($podStatus -notmatch "Running") {
    Out-Both "[!!] Dev pod is not running. Start it first (make up)."
    if (-not $NoPause) { Write-Host "`n  Press Enter to close..."; Read-Host | Out-Null }
    exit 1
}
Out-Both ""

# ── Target selection ────────────────────────────────────────────────────────
if (-not $Target) {
    Write-Host "  Which target?"
    Write-Host "    [1] watch (all)      [4] logs-caddy"
    Write-Host "    [2] logs-api         [5] logs-heartbeat"
    Write-Host "    [3] logs-ui          [6] status"
    Write-Host ""
    $choice = Read-Host "  Choice (1-6)"
    $Target = switch ($choice) {
        "1" { "watch" }
        "2" { "logs-api" }
        "3" { "logs-ui" }
        "4" { "logs-caddy" }
        "5" { "logs-heartbeat" }
        "6" { "status" }
        default { "watch" }
    }
}

Out-Both "Target: make $Target"
Out-Both "Max lines: $MaxLines"
Out-Both ""

# ── Capture ─────────────────────────────────────────────────────────────────
$stats = @{
    Total = 0; Clean = 0; HasCR = 0; HasLF = 0; HasESC = 0
    CursorMove = 0; CursorCol = 0; MultiChunk = 0
    NonAscii = 0; LongLines = 0
}

Out-Both "=================================================================="
Out-Both "CAPTURE MODE: analyzing first $MaxLines pipeline objects"
Out-Both "=================================================================="
Out-Both ""

# Use a timeout in WSL as safety net so the pipeline eventually ends.
# Select-Object -First N terminates the pipeline after N objects.
$timeout = [Math]::Max(15, $MaxLines)   # seconds, generous for slow output

function Analyze-Line {
    param([string]$raw)
    $len   = $raw.Length
    $flags = Get-LineFlags $raw

    $display = if ($len -gt 140) { $raw.Substring(0, 140) + "..." } else { $raw }
    $flagStr = if ($flags.Count -gt 0) { " [$($flags -join ', ')]" } else { "" }

    Out-Both "--- #$($stats.Total) (len=$len)$flagStr ---"
    Out-Both "  |$display|"

    # Show details for flagged lines (skip if the only flag is LONG)
    $interesting = $flags | Where-Object { $_ -notmatch "^LONG" }
    if ($interesting) {
        Out-Both "  ctrl: $(Get-ControlChars $raw)"
        $ansi = Get-AnsiReport $raw
        if ($ansi) { Out-Both "  ansi: $ansi" }
        Out-Both "  $(Get-HexDump $raw)"
    }

    # Split check
    $subs = ($raw -replace "`r`n", "`n") -replace "`r", "`n" -split "`n" |
        Where-Object { $_ -ne '' }
    if ($subs.Count -gt 1) {
        Out-Both "  SPLITS INTO $($subs.Count) sub-lines:"
        for ($j = 0; $j -lt [Math]::Min($subs.Count, 5); $j++) {
            $sub = $subs[$j]
            if ($sub.Length -gt 100) { $sub = $sub.Substring(0, 100) + "..." }
            Out-Both "    [$j]: |$sub|"
        }
    }
    Out-Both ""

    # Update stats
    $stats.Total++
    if ($flags.Count -eq 0) { $stats.Clean++ }
    foreach ($f in $flags) {
        if ($f -match "BARE_CR|MIXED_CR|CR_OVER") { $stats.HasCR++ }
        if ($f -eq "EMBEDDED_LF")                 { $stats.HasLF++ }
        if ($f -eq "CURSOR_MOVE")                 { $stats.CursorMove++ }
        if ($f -match "CURSOR_COL|CURSOR_FWD")    { $stats.CursorCol++ }
        if ($f -eq "NON_ASCII")                   { $stats.NonAscii++ }
        if ($f -match "^LONG")                    { $stats.LongLines++ }
    }
    if ($raw -match '\x1b') { $stats.HasESC++ }
}

try {
    # Select-Object -First properly terminates the pipeline after N items
    $lines = wsl bash -c "cd '$wslPath' && timeout $timeout make $Target 2>&1" |
        Select-Object -First $MaxLines

    foreach ($raw in $lines) {
        if ($raw -is [string]) {
            Analyze-Line $raw
        }
    }
} catch {
    Out-Both ">>> Stopped: $($_.Exception.Message)"
}

# ============================================================================
# SUMMARY & DIAGNOSIS
# ============================================================================

Out-Both ""
Out-Both "=================================================================="
Out-Both "SUMMARY ($($stats.Total) lines captured)"
Out-Both "=================================================================="
Out-Both ""
Out-Both "  Clean lines:          $($stats.Clean)"
Out-Both "  Bare CR (\\r):        $($stats.HasCR)$(if ($stats.HasCR) { '  <-- causes cursor-to-col-0 jumps' })"
Out-Both "  Embedded LF:          $($stats.HasLF)$(if ($stats.HasLF) { '  <-- multi-line chunks from WSL' })"
Out-Both "  ESC sequences:        $($stats.HasESC)"
Out-Both "  Cursor positioning:   $($stats.CursorCol)$(if ($stats.CursorCol) { '  <-- MAIN cause of random columns!' })"
Out-Both "  Non-ASCII (UTF-8):    $($stats.NonAscii)$(if ($stats.NonAscii -and $cpOut -ne 65001) { '  <-- garbled under CP ' + $cpOut })"
Out-Both "  Long lines (>200ch):  $($stats.LongLines)$(if ($stats.LongLines) { '  <-- wraps at col ' + $conW + ', looks misaligned' })"
Out-Both ""

# ── Root cause determination ────────────────────────────────────────────────
Out-Both "=================================================================="
Out-Both "DIAGNOSIS"
Out-Both "=================================================================="
Out-Both ""

$foundCause = $false

if ($stats.CursorCol -gt 0) {
    $foundCause = $true
    Out-Both "[CAUSE] ANSI CURSOR POSITIONING SEQUENCES"
    Out-Both "  Containers emit ESC[nG or ESC[nC codes that move the cursor"
    Out-Both "  to specific columns. Even though Strip-Ansi catches these"
    Out-Both "  for the launcher.ps1 formatted view, if you're running"
    Out-Both "  'make watch' or 'wsl podman pod logs -f' directly, the raw"
    Out-Both "  codes reach the console and shift each line to a random column."
    Out-Both ""
}

if ($stats.HasCR -gt 0) {
    $foundCause = $true
    Out-Both "[CAUSE] CARRIAGE RETURN WITHOUT NEWLINE"
    Out-Both "  Lines contain \\r without \\n. The cursor returns to column 0"
    Out-Both "  and subsequent text overwrites from the left. Common with"
    Out-Both "  progress bars (npm, pip) and status spinners."
    Out-Both ""
}

if ($stats.HasLF -gt 0) {
    $foundCause = $true
    Out-Both "[CAUSE] MULTI-LINE CHUNKS"
    Out-Both "  WSL delivers multiple log lines as a single string. If not"
    Out-Both "  split before display, the whole chunk appears as one wrapped"
    Out-Both "  line. The launcher.ps1 Invoke-Make function splits on \\n,"
    Out-Both "  but direct 'make watch' from CMD does not."
    Out-Both ""
}

if ($stats.NonAscii -gt 0 -and $cpOut -ne 65001) {
    $foundCause = $true
    Out-Both "[CAUSE] ENCODING MISMATCH (CP $cpOut vs UTF-8)"
    Out-Both "  Console uses CP $cpOut but containers output UTF-8."
    Out-Both "  Multi-byte characters (like Vite's arrow) get decoded"
    Out-Both "  as multiple wrong characters, garbling the display and"
    Out-Both "  throwing off column counts."
    Out-Both ""
}

if ($stats.LongLines -gt 0) {
    $foundCause = $true
    Out-Both "[CAUSE] LINE WRAPPING"
    Out-Both "  Caddy JSON logs are 200+ chars. In a ${conW}-column console,"
    Out-Both "  they wrap to multiple visual lines. Mixed with short lines"
    Out-Both "  from other containers, this looks like random positioning."
    Out-Both ""
}

if (-not $foundCause) {
    if ($stats.Total -eq 0) {
        Out-Both "[?] NO DATA CAPTURED"
        Out-Both "  The pod might not be producing logs. Try:"
        Out-Both "  - Opening the app in a browser to trigger request logs"
        Out-Both "  - Using -Target logs-api or -Target logs-caddy"
        Out-Both "  - Increasing -MaxLines"
    } else {
        Out-Both "[OK] NO ISSUES FOUND IN CAPTURED DATA"
        Out-Both "  All $($stats.Total) lines are clean. The problem may be:"
        Out-Both "  - Intermittent (occurs during HMR updates or specific requests)"
        Out-Both "  - Only visible in a real CMD window (not captured in pipeline)"
        Out-Both "  - Caused by the console width being too narrow"
        Out-Both ""
        Out-Both "  Try running with -MaxLines 200 and triggering activity in the app."
    }
    Out-Both ""
}

# ============================================================================
# FIXES
# ============================================================================

Out-Both "=================================================================="
Out-Both "RECOMMENDED FIXES"
Out-Both "=================================================================="
Out-Both ""

Out-Both "If running 'make watch' or 'podman pod logs' directly from CMD:"
Out-Both ""
Out-Both "  1. Set UTF-8 first:  chcp 65001"
Out-Both "  2. Use TERM=dumb:    wsl bash -c 'TERM=dumb podman pod logs -f research-ai-dev'"
Out-Both "  3. Widen console:    mode con: cols=220"
Out-Both ""
Out-Both "If using the launcher (run-dev.bat / launcher.ps1):"
Out-Both ""
Out-Both "  The launcher already strips ANSI and formats output."
Out-Both "  If it still looks broken, add this near the top of launcher.ps1:"
Out-Both ""
Out-Both "    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8"
Out-Both "    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8"
Out-Both ""
Out-Both "  The chcp 65001 in run-dev.bat sets the CMD codepage but"
Out-Both "  PowerShell's [Console]::OutputEncoding stays at CP 850"
Out-Both "  unless explicitly overridden."
Out-Both ""
Out-Both "Quick test (paste in CMD to see if it fixes it):"
Out-Both ""
Out-Both "  chcp 65001 && wsl bash -c 'TERM=dumb podman pod logs -f research-ai-dev'"
Out-Both ""

Out-Both "=================================================================="
Out-Both "END - saved to: $outFile"
Out-Both "=================================================================="

Write-Host ""
Write-Host "  Full report: $outFile"
Write-Host ""

if (-not $NoPause) {
    Write-Host "  Press Enter to close..."
    Read-Host | Out-Null
}
