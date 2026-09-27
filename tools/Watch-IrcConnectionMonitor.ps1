# Persistent IRC connection detector for watch-grok. Emits FAIL/DONE on state change.
# CAST IRON (marchhare 2026-09-27): do not Heal on a single flaky CIM miss - stacked
# -Heal/-Reload orphan-prunes kill the live irc_agent the first Reload just started.
# Never name a param $Home (PS5.1 read-only automatic variable).
param(
    [int]$IntervalSeconds = 45,
    [int]$FailStreakBeforeHeal = 2,
    [int]$HealCooldownSeconds = 120
)
$ErrorActionPreference = 'Continue'
$waw = Join-Path $PSScriptRoot 'Watch-AgentWatcher.ps1'
$ircHome = Join-Path $env:USERPROFILE '.agentic-irc-watch-grok'
$prev = ''
$failStreak = 0
$lastHealUtc = [datetime]::MinValue

function Read-CoordPids {
    param([string]$SeatHome)
    $doc = @{ seat = 0; irc_agent = 0; listen = 0 }
    $path = Join-Path $SeatHome 'coordinator.pid'
    if (-not (Test-Path -LiteralPath $path)) { return $doc }
    foreach ($line in @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
        if ($line -match '^(seat|irc_agent|listen)=(\d+)\s*$') {
            $doc[$Matches[1]] = [int]$Matches[2]
        }
    }
    return $doc
}

function Test-PidAlive {
    param([int]$Id)
    if ($Id -le 0) { return $false }
    return $null -ne (Get-Process -Id $Id -ErrorAction SilentlyContinue)
}

function Get-IrcAgentCount {
    param([string]$SeatHome)
    $esc = [regex]::Escape([IO.Path]::GetFullPath($SeatHome).TrimEnd('\'))
    $cim = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            $cl -match 'irc_agent\.py' -and $cl -match $esc
        })
    if ($cim.Count -gt 0) { return $cim.Count }
    $coord = Read-CoordPids -SeatHome $SeatHome
    if (Test-PidAlive -Id $coord.irc_agent) { return 1 }
    return 0
}

function Get-WatchWorkerCount {
    $cim = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            $cl -match 'Watch-AgentHealth\.ps1' -and $cl -match '-WatchWorker'
        })
    return $cim.Count
}

while ($true) {
    Start-Sleep -Seconds ([Math]::Max(15, $IntervalSeconds))
    $agN = Get-IrcAgentCount -SeatHome $ircHome
    $monN = Get-WatchWorkerCount
    $coord = Read-CoordPids -SeatHome $ircHome
    # Prefer coordinator Get-Process when CIM under-counts (slow/flaky on marchhare).
    if ($agN -eq 0 -and (Test-PidAlive -Id $coord.irc_agent)) { $agN = 1 }
    $st = if ($agN -gt 0 -and $monN -gt 0) { 'OK' } else { 'FAIL' }

    if ($st -eq 'OK') {
        $failStreak = 0
        if ($st -ne $prev) {
            Write-Output ("DONE recovered irc={0} mon={1}" -f $agN, $monN)
        }
        $prev = $st
        continue
    }

    $failStreak++
    if ($failStreak -lt [Math]::Max(1, $FailStreakBeforeHeal)) {
        # Debounce: one miss is not a crash (CIM lag / Reload race).
        continue
    }

    $now = [datetime]::UtcNow
    if (($now - $lastHealUtc).TotalSeconds -lt [Math]::Max(30, $HealCooldownSeconds)) {
        continue
    }

    if ($st -ne $prev) {
        Write-Output ("FAILED irc={0} mon={1} streak={2}" -f $agN, $monN, $failStreak)
    }
    $prev = $st

    if (Test-Path -LiteralPath $waw) {
        try {
            $lastHealUtc = $now
            & powershell -NoProfile -ExecutionPolicy Bypass -File $waw -Once -Heal | Out-Null
        }
        catch { }
    }
}
