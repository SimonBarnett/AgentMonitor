# Smoke test for tools/Watch-AgentWatcher.ps1 (meta-monitor).
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $RepoRoot 'tools\Watch-AgentWatcher.ps1'
if (-not (Test-Path -LiteralPath $script)) { throw 'missing Watch-AgentWatcher.ps1' }
$src = Get-Content -LiteralPath $script -Raw
if ($src -match '\[string\]\$Home\b') { throw 'must not use $Home param (PS5.1 read-only)' }
if ($src -notmatch 'coord-agent-ne-seat') { throw 'must detect agent= != seat= failure mode' }
if ($src -notmatch 'Watch-AgentWatcher\.log') { throw 'must write Watch-AgentWatcher.log' }
if ($src -notmatch '-Reload') { throw 'heal path must Reload Watch-AgentHealth' }

$tmp = Join-Path $env:TEMP ('waw-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $fakeHome = Join-Path $tmp 'home'
    New-Item -ItemType Directory -Force -Path $fakeHome | Out-Null
    @(
        'nick=marchhare-1'
        'seat=1'
        'listen='
        'agent=99999'
        'irc_agent='
        "home=$fakeHome"
        'channels=#marchhare'
    ) | Set-Content (Join-Path $fakeHome 'coordinator.pid') -Encoding utf8
    $fakeLog = Join-Path $tmp 'Watch-AgentHealth.log'
    Set-Content $fakeLog -Value '2026-01-01T00:00:00Z bind slot=1' -Encoding utf8
    $fakeScript = Join-Path $tmp 'Watch-AgentHealth.ps1'
    Set-Content $fakeScript -Value '# stub' -Encoding utf8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Once `
        -IrcHome $fakeHome -WatchScript $fakeScript -WatchLog $fakeLog | Out-Null
    $wlog = Join-Path $tmp 'Watch-AgentWatcher.log'
    if (-not (Test-Path -LiteralPath $wlog)) { throw 'watcher log not created' }
    $raw = Get-Content $wlog -Raw
    if ($raw -notmatch 'status=FAIL') { throw 'expected FAIL for dead seat + agent!=seat' }
    if ($raw -notmatch 'coord-agent-ne-seat') { throw 'expected coord-agent-ne-seat reason' }
    Write-Host 'PASS Test-WatchAgentWatcher'
    exit 0
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
