<#
.SYNOPSIS
  Meta-monitor for Watch-AgentHealth (agent watcher): process + IRC + log signals.

.DESCRIPTION
  CAST IRON companion (Simon 2026-09-26): when the seat watcher dies or IRC PARTs
  "seat ended", log WHY to Watch-AgentWatcher.log. Optional -Heal restarts IRC
  ensure path by relaunching Watch-AgentHealth -Reload (does not replace the TUI).

  Findings hotfixed alongside this tool:
  - coordinator agent= must be live TUI seat (not irc_agent pid) or PART seat ended
  - never name a param $Home (PS5.1 read-only) - use SeatHome
  - irc-health lines in Watch-AgentHealth.log for diagnosis

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Watch-AgentWatcher.ps1 -Once
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Watch-AgentWatcher.ps1 -IntervalSeconds 30
#>
[CmdletBinding()]
param(
    [string]$IrcHome = '',
    [string]$WatchScript = '',
    [string]$WatchLog = '',
    [string]$StateDir = '',
    [int]$IntervalSeconds = 30,
    [switch]$Once,
    [switch]$Heal,
    [switch]$Grok
)

$ErrorActionPreference = 'Continue'
if (-not $IrcHome) {
    $IrcHome = Join-Path $env:USERPROFILE '.agentic-irc-watch-grok'
}
if (-not $WatchScript) {
    $cand = @(
        (Join-Path $env:USERPROFILE 'Desktop\Watch-AgentHealth\Watch-AgentHealth.ps1'),
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'Watch-AgentHealth.ps1')
    )
    foreach ($c in $cand) { if (Test-Path -LiteralPath $c) { $WatchScript = $c; break } }
}
if (-not $WatchLog) {
    $WatchLog = Join-Path (Split-Path $WatchScript -Parent) 'Watch-AgentHealth.log'
}
if (-not $StateDir) {
    $StateDir = Join-Path $env:USERPROFILE '.grok\agent-health\watch-grok-1'
}
$outLog = Join-Path (Split-Path $WatchLog -Parent) 'Watch-AgentWatcher.log'
if (-not (Test-Path -LiteralPath (Split-Path $outLog -Parent))) {
    New-Item -ItemType Directory -Force -Path (Split-Path $outLog -Parent) | Out-Null
}

function Write-WatcherLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date).ToUniversalTime().ToString('o'), $Message
    Add-Content -LiteralPath $outLog -Value $line -Encoding utf8
    Write-Output $line
}

function Get-WatchWorkerRows {
    return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            $cl -match 'Watch-AgentHealth\.ps1' -and $cl -match '-WatchWorker'
        })
}

function Get-IrcAgentRows {
    param([string]$SeatHomePath)
    $esc = [regex]::Escape([IO.Path]::GetFullPath($SeatHomePath).TrimEnd('\'))
    return @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            $cl -match 'irc_agent\.py' -and $cl -match $esc
        })
}

function Get-IrcListenRows {
    param([string]$SeatHomePath)
    $esc = [regex]::Escape([IO.Path]::GetFullPath($SeatHomePath).TrimEnd('\'))
    return @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            $cl -match 'irc_listen\.py' -and $cl -match $esc
        })
}

function Read-Coordinator {
    param([string]$SeatHomePath)
    $path = Join-Path $SeatHomePath 'coordinator.pid'
    $doc = @{ nick = ''; seat = ''; agent = ''; irc_agent = ''; listen = '' }
    if (-not (Test-Path -LiteralPath $path)) { return $doc }
    foreach ($line in @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
        if ($line -match '^(nick|seat|agent|irc_agent|listen)=(.*)$') {
            $doc[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $doc
}

function Test-SeatAlive {
    param([string]$Seat)
    $n = 0
    if (-not [int]::TryParse($Seat, [ref]$n)) { return $false }
    if ($n -le 0) { return $false }
    return $null -ne (Get-Process -Id $n -ErrorAction SilentlyContinue)
}

function Get-LastWatchLogSignals {
    param([string]$LogPath)
    $hit = @{ health = ''; part = ''; err = ''; bored = '' }
    if (-not (Test-Path -LiteralPath $LogPath)) { return $hit }
    $tail = @(Get-Content -LiteralPath $LogPath -Tail 40 -ErrorAction SilentlyContinue)
    $hit.health = [string](@($tail | Where-Object { $_ -match 'irc-health' } | Select-Object -Last 1))
    $hit.part = [string](@($tail | Where-Object { $_ -match 'seat ended|PART|Disconnect|irc graceful' } | Select-Object -Last 1))
    $hit.err = [string](@($tail | Where-Object { $_ -match 'Cannot overwrite|PARSE|watch fatal|watch loop error' } | Select-Object -Last 1))
    $hit.bored = [string](@($tail | Where-Object { $_ -match 'bored ->' } | Select-Object -Last 1))
    return $hit
}

function Invoke-WatcherCheck {
    $workers = @(Get-WatchWorkerRows)
    $agents = @(Get-IrcAgentRows -SeatHomePath $IrcHome)
    $listens = @(Get-IrcListenRows -SeatHomePath $IrcHome)
    $coord = Read-Coordinator -SeatHomePath $IrcHome
    $seatAlive = Test-SeatAlive -Seat ([string]$coord.seat)
    $agentFieldIsHost = ($coord.agent -eq $coord.seat) -and ($coord.seat -ne '')
    $signals = Get-LastWatchLogSignals -LogPath $WatchLog
    $ircLog = Join-Path $IrcHome 'irc.log'
    $lastPart = ''
    if (Test-Path -LiteralPath $ircLog) {
        $lastPart = [string](@(Get-Content -LiteralPath $ircLog -Tail 15 -ErrorAction SilentlyContinue |
                Where-Object { $_ -match 'PART|seat ended' } | Select-Object -Last 1))
    }

    $status = 'OK'
    $reasons = @()
    if ($workers.Count -eq 0) { $status = 'FAIL'; $reasons += 'watch-worker-missing' }
    if ($agents.Count -eq 0) { $status = 'FAIL'; $reasons += 'irc-agent-missing' }
    if ($listens.Count -eq 0) { $status = 'FAIL'; $reasons += 'irc-listen-missing' }
    if (-not $seatAlive) { $status = 'FAIL'; $reasons += 'seat-pid-dead' }
    if ($coord.agent -and $coord.seat -and ($coord.agent -ne $coord.seat)) {
        # Stale pattern that caused PART seat ended
        $status = 'FAIL'
        $reasons += 'coord-agent-ne-seat'
    }
    if ($lastPart -match 'seat ended') {
        $status = 'FAIL'
        $reasons += 'irc-log-seat-ended'
    }
    if ($signals.err) { $status = 'FAIL'; $reasons += 'watch-log-error' }

    $msg = ('status={0} reasons={1} workers={2} irc_agent={3} listen={4} seat={5} seatAlive={6} agentFieldIsHost={7} coordAgent={8} coordIrcAgent={9}' -f `
            $status,
        (($reasons -join ',') ),
        $workers.Count,
        $(if ($agents.Count) { $agents[0].ProcessId } else { 0 }),
        $(if ($listens.Count) { $listens[0].ProcessId } else { 0 }),
        $coord.seat,
        $seatAlive,
        $agentFieldIsHost,
        $coord.agent,
        $coord.irc_agent)
    Write-WatcherLog $msg
    if ($signals.health) { Write-WatcherLog ('last-irc-health: {0}' -f $signals.health.Substring(0, [Math]::Min(200, $signals.health.Length))) }
    if ($lastPart) { Write-WatcherLog ('last-irc-part: {0}' -f $lastPart.Substring(0, [Math]::Min(160, $lastPart.Length))) }
    if ($signals.err) { Write-WatcherLog ('last-watch-err: {0}' -f $signals.err.Substring(0, [Math]::Min(160, $signals.err.Length))) }

    if ($Heal -and $status -eq 'FAIL' -and $WatchScript -and (Test-Path -LiteralPath $WatchScript)) {
        Write-WatcherLog ('heal: launching Watch-AgentHealth -Reload -IrcHome {0}' -f $IrcHome)
        $args = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
            '-File', $WatchScript,
            '-WatchWorker', '-Grok', '-Windows', 'off', '-Reload',
            '-IrcHome', $IrcHome
        )
        Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList $args -WindowStyle Hidden | Out-Null
    }

    return [pscustomobject]@{
        status           = $status
        reasons          = $reasons
        workerCount      = $workers.Count
        agentCount       = $agents.Count
        listenCount      = $listens.Count
        seatAlive        = $seatAlive
        agentFieldIsHost = $agentFieldIsHost
    }
}

Write-WatcherLog ('watch-agent-watcher start ircHome={0} watchScript={1} interval={2} heal={3}' -f $IrcHome, $WatchScript, $IntervalSeconds, [bool]$Heal)
do {
    $null = Invoke-WatcherCheck
    if ($Once) { break }
    Start-Sleep -Seconds ([Math]::Max(10, $IntervalSeconds))
} while ($true)
