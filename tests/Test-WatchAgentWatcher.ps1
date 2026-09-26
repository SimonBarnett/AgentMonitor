$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script = Join-Path $RepoRoot "tools\Watch-AgentWatcher.ps1"
$src = Get-Content -LiteralPath $script -Raw
if ($src -match "param\(\[string\]\`$Home\)") { throw "must not use param([string]`$Home)" }
if ($src -notmatch "coord-agent-ne-seat") { throw "must detect agent= != seat=" }
if ($src -notmatch "Watch-AgentWatcher\.log") { throw "must write log" }
$tmp = Join-Path $env:TEMP ("waw-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  $fakeHome = Join-Path $tmp "home"
  New-Item -ItemType Directory -Force -Path $fakeHome | Out-Null
  @("nick=marchhare-1";"seat=1";"listen=";"agent=99999";"irc_agent=";"home=$fakeHome";"channels=#marchhare") | Set-Content (Join-Path $fakeHome "coordinator.pid") -Encoding utf8
  $fakeLog = Join-Path $tmp "Watch-AgentHealth.log"; Set-Content $fakeLog "x" -Encoding utf8
  $fakeScript = Join-Path $tmp "Watch-AgentHealth.ps1"; Set-Content $fakeScript "# stub" -Encoding utf8
  & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Once -IrcHome $fakeHome -WatchScript $fakeScript -WatchLog $fakeLog | Out-Null
  $wlog = Join-Path $tmp "Watch-AgentWatcher.log"
  $raw = Get-Content $wlog -Raw
  if ($raw -notmatch "status=FAIL") { throw "expected FAIL" }
  if ($raw -notmatch "coord-agent-ne-seat") { throw "expected coord-agent-ne-seat" }
  Write-Host "PASS Test-WatchAgentWatcher"
} finally { Remove-Item $tmp -Recurse -Force -EA SilentlyContinue }
