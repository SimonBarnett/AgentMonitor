# MRB #140 / issue #139: stacked Heal/Reload must not kill live irc_agent.
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$wah = Get-Content -LiteralPath (Join-Path $RepoRoot "Watch-AgentHealth.ps1") -Raw
if ($wah -notmatch 'leave IRC for Ensure adopt') {
    throw "Stop-OrphanWatchPythonForHome must skip prune when seat TUI is live"
}
if ($wah -notmatch 'coordAlive') {
    throw "prune skip must honor coordinator irc_agent/listen Get-Process fallback"
}

$waw = Get-Content -LiteralPath (Join-Path $RepoRoot "tools\Watch-AgentWatcher.ps1") -Raw
if ($waw -notmatch 'Test-CoordPidAlive') {
    throw "Watch-AgentWatcher must fall back to coordinator PIDs when CIM empty"
}
if ($waw -notmatch 'heal: skipped \(cooldown') {
    throw "Watch-AgentWatcher -Heal must debounce with cooldown"
}
if ($waw -notmatch 'heal: skipped \(watch worker already live\)') {
    throw "Watch-AgentWatcher -Heal must skip when worker already live"
}

$mon = Get-Content -LiteralPath (Join-Path $RepoRoot "tools\Watch-IrcConnectionMonitor.ps1") -Raw
if ($mon -notmatch 'FailStreakBeforeHeal') {
    throw "IrcConnectionMonitor must debounce FAIL streak before Heal"
}
if ($mon -notmatch 'HealCooldownSeconds') {
    throw "IrcConnectionMonitor must cooldown Heal launches"
}
if ($mon -notmatch 'Read-CoordPids') {
    throw "IrcConnectionMonitor must use coordinator Get-Process fallback"
}

# Runtime: heal cooldown stamp prevents a second immediate Heal.
$tmp = Join-Path $env:TEMP ("heal140-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $fakeHome = Join-Path $tmp "home"
    New-Item -ItemType Directory -Force -Path $fakeHome | Out-Null
    # agent=seat so we do not trip coord-agent-ne-seat; still FAIL on missing workers/irc
    @(
        "nick=marchhare-1"
        "seat=1"
        "listen="
        "agent=1"
        "irc_agent="
        "home=$fakeHome"
        "channels=#marchhare"
    ) | Set-Content (Join-Path $fakeHome "coordinator.pid") -Encoding utf8
    $fakeLog = Join-Path $tmp "Watch-AgentHealth.log"
    Set-Content $fakeLog "x" -Encoding utf8
    $fakeScript = Join-Path $tmp "Watch-AgentHealth.ps1"
    Set-Content $fakeScript "# stub" -Encoding utf8
    $stamp = Join-Path $env:TEMP "Watch-AgentWatcher-lastHeal.utc"
    Set-Content -LiteralPath $stamp -Value ([datetime]::UtcNow.ToString("o")) -Encoding ascii
    $script = Join-Path $RepoRoot "tools\Watch-AgentWatcher.ps1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Once -Heal `
        -IrcHome $fakeHome -WatchScript $fakeScript -WatchLog $fakeLog | Out-Null
    $wlog = Join-Path $tmp "Watch-AgentWatcher.log"
    if (-not (Test-Path $wlog)) { $wlog = Join-Path (Split-Path $fakeLog -Parent) "Watch-AgentWatcher.log" }
    # Watcher writes beside WatchLog parent - Desktop path uses Split-Path WatchLog
    $candidates = @(
        (Join-Path $tmp "Watch-AgentWatcher.log"),
        (Join-Path (Split-Path $fakeLog -Parent) "Watch-AgentWatcher.log")
    )
    $raw = $null
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { $raw = Get-Content -LiteralPath $c -Raw; break }
    }
    if (-not $raw) { throw "watcher log missing" }
    if ($raw -notmatch "heal: skipped \(cooldown") {
        throw "expected heal cooldown skip in watcher log"
    }
    Write-Host "PASS Test-WatchHealReloadPreserveIrc"
}
finally {
    Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
}
