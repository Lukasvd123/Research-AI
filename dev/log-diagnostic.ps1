#Requires -Version 5.1
# ============================================================================
# Log Output Diagnostic - captures exactly what WSL sends to PowerShell
# ============================================================================
# Place this in the dev\ folder next to launcher.ps1
# Run:  .\log-diagnostic.ps1
# Or:   powershell -NoProfile -ExecutionPolicy Bypass -File "dev\log-diagnostic.ps1"
# Output goes to dev\logs\diagnostic_<timestamp>.txt
# ============================================================================

param(
    [switch]$RawBytes   # pass -RawBytes for hex dump of each line
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSScriptRoot
$devDir    = $PSScriptRoot

# resolve WSL path
$p = $scriptDir -replace '\\', '/'
if ($p -match '^([A-Za-z]):(.*)') {
    $drive = $Matches[1].ToLower()
    $rest  = $Matches[2]
    $wslPath = "/mnt/$drive$rest"
} else {
    $wslPath = $p
}

$logDir = Join-Path $devDir "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$outFile = Join-Path $logDir "diagnostic_$ts.txt"

function Dump {
    param([string]$Text)
    $Text | Out-File -Append -FilePath $outFile -Encoding utf8
    Write-Host $Text
}

Clear-Host
Write-Host ""
Write-Host "  Log Output Diagnostic"
Write-Host "  Output file: $outFile"
Write-Host "  WSL path:    $wslPath"
Write-Host ""

Dump "============================================"
Dump "DIAGNOSTIC RUN: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Dump "WSL path: $wslPath"
Dump "PowerShell version: $($PSVersionTable.PSVersion)"
Dump "Host: $($Host.Name)"
Dump "Console OutputEncoding: $([Console]::OutputEncoding.EncodingName)"
Dump "Console InputEncoding:  $([Console]::InputEncoding.EncodingName)"
Dump "============================================"
Dump ""

$choice = Read-Host "  Which target? [1] logs-caddy  [2] logs-api  [3] logs-ui  [4] watch (all)  [5] status"
$target = switch ($choice) {
    "1" { "logs-caddy" }
    "2" { "logs-api" }
    "3" { "logs-ui" }
    "4" { "watch" }
    "5" { "status" }
    default { "logs-caddy" }
}

Dump ">>> TARGET: make $target"
Dump ">>> Capturing up to 50 lines (Ctrl+C to stop early)..."
Dump ">>> Each line shows type, length, content, and regex match results"
Dump ""

$lineCount = 0
$maxLines = 50

try {
    wsl bash -c "cd '$wslPath' && make $target 2>&1" 2>$null | ForEach-Object {
        if ($lineCount -ge $maxLines) { return }

        $raw = $_
        $type = $raw.GetType().FullName
        $len  = if ($raw -is [string]) { $raw.Length } else { "N/A" }

        Dump "--- LINE $lineCount ---"
        Dump "  type:    $type"
        Dump "  length:  $len"
        Dump "  raw:     |$raw|"

        # does it contain a curly brace at all
        $hasJson = $false
        if ($raw -match '\{') { $hasJson = $true }
        Dump "  hasJson: $hasJson"

        # test pattern 1: hex container ID + space + JSON object
        $m1 = $raw -match '^([0-9a-fA-F]{8,64})\s+(\{.+\})\s*$'
        Dump "  regex1 (id+json):   $m1"
        if ($m1) {
            Dump "    capturedId:   |$($Matches[1])|"
            $jsnip = $Matches[2]
            if ($jsnip.Length -gt 120) { $jsnip = $jsnip.Substring(0, 120) + "..." }
            Dump "    capturedJson: |$jsnip|"
        }

        # test pattern 2: bare JSON with "level" key
        $m2 = $raw -match '^\{.+"level"\s*:.+\}\s*$'
        Dump "  regex2 (bare json): $m2"

        # check if WSL delivers multi-line chunks in one string
        $sublines = ($raw -replace "`r`n", "`n") -replace "`r", "`n" -split "`n"
        Dump "  sublines: $($sublines.Count)"
        if ($sublines.Count -gt 1) {
            for ($i = 0; $i -lt [Math]::Min($sublines.Count, 5); $i++) {
                $sub = $sublines[$i]
                if ($sub.Length -gt 100) { $sub = $sub.Substring(0, 100) + "..." }
                Dump "    sub[$i]: |$sub|"
            }
        }

        # try to find and parse JSON
        if ($hasJson) {
            $jsonStr = $null
            if ($m1) {
                $jsonStr = $Matches[2]
            } elseif ($m2) {
                $jsonStr = $raw.Trim()
            } else {
                $idx = $raw.IndexOf('{')
                if ($idx -ge 0) {
                    $candidate = $raw.Substring($idx)
                    $csnip = $candidate
                    if ($csnip.Length -gt 120) { $csnip = $csnip.Substring(0, 120) + "..." }
                    Dump "  jsonCandidate (from idx $idx): |$csnip|"
                    $jsonStr = $candidate
                }
            }

            if ($jsonStr) {
                try {
                    $obj = $jsonStr | ConvertFrom-Json
                    Dump "  jsonParse: OK"
                    Dump "    .level:  |$($obj.level)|"
                    Dump "    .msg:    |$($obj.msg)|"
                    Dump "    .logger: |$($obj.logger)|"
                    Dump "    .ts:     |$($obj.ts)|"
                } catch {
                    Dump "  jsonParse: FAILED - $($_.Exception.Message)"
                }
            }
        }

        # optional hex dump of first 80 bytes
        if ($RawBytes -and $raw -is [string] -and $raw.Length -gt 0) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
            $count = [Math]::Min(80, $bytes.Length)
            $hexPart = ($bytes[0..($count - 1)] | ForEach-Object { "{0:X2}" -f $_ }) -join " "
            Dump "  hex($count): $hexPart"
        }

        Dump ""
        $lineCount++
    }
} catch {
    Dump ">>> CAUGHT ERROR: $_"
}

Dump ""
Dump ">>> Done. Captured $lineCount lines."
Dump "============================================"

Write-Host ""
Write-Host "  Done - captured $lineCount lines."
Write-Host "  Output: $outFile"
Write-Host ""
Write-Host "  Press Enter to close..."
Read-Host | Out-Null
