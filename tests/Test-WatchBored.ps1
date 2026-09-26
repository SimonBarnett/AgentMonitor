# FR #100: monitor-owned !bored (start / DONE / idle), own #{machine} only.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchBored.ps1
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$path = Join-Path $RepoRoot 'Watch-AgentHealth.ps1'
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
$fail = 0

function Check([string]$Id, [scriptblock]$Body) {
    try { & $Body; Write-Host "PASS $Id" } catch { $script:fail++; Write-Host "FAIL $Id :: $($_.Exception.Message)" }
}

function Get-Fn([string]$Name) {
    $f = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $Name }, $true)
    if (-not $f) { throw "function $Name missing from Watch-AgentHealth.ps1" }
    return $f
}

# Dot-source into script scope (a nested Import function would drop the defs on return).
foreach ($n in @(
        'Get-WatchSeatChannels',
        'Get-WatchOutboxPayload',
        'Get-WatchOutboxRows',
        'Test-WatchSeatOpenAck',
        'Get-WatchBoredChannel',
        'Send-WatchIrcBored',
        'Get-WatchOutboxDoneKey',
        'Test-WatchSeatBoredBusy',
        'Test-WatchAgentWakeBusy',
        'Test-CursorAgentForwardBusy',
        'Get-WatchSeatNick',
        'Test-WatchNoBored',
        'Sync-WatchBored'
    )) {
    . ([scriptblock]::Create((Get-Fn $n).Extent.Text))
}
function Write-WatchLog { param([string]$Message) }
function Get-WatchMachineId { return 'marchhare' }
function Test-ForbiddenIrcHome { param([string]$ResolvedHome) return $false }
function Test-CursorAgentForwardBusy { param([string]$SessionId) return $false }
function Test-WatchAgentWakeBusy { param([string]$SessionId, [switch]$GrokKind) return $false }
$script:BoredIdleSeconds = 120
$script:BoredRepeatSeconds = 180
$script:BoredAckStaleMinutes = 45
$script:KindName = 'grok'
$script:NoBored = $false
$script:WatchChannelOverride = $null
$script:WatchNickOverride = $null

Check 'AM100a Send-WatchIrcBored writes PRIVMSG #machine :!bored only' {
    $seatDir = Join-Path ([IO.Path]::GetTempPath()) ('am100-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $seatDir | Out-Null
    try {
        $ok = Send-WatchIrcBored -IrcHome $seatDir -Channel '#marchhare' -Reason 'start' -OurNick 'marchhare-1'
        if (-not $ok) { throw 'expected send ok' }
        $lines = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8)
        if ($lines.Count -ne 1) { throw "expected 1 line, got $($lines.Count)" }
        if ($lines[0] -ne 'PRIVMSG #marchhare :!bored') { throw "bad line: $($lines[0])" }
        $bad = Send-WatchIrcBored -IrcHome $seatDir -Channel '#bobiverse' -Reason 'idle'
        if ($bad) { throw 'must refuse #bobiverse' }
        $bad2 = Send-WatchIrcBored -IrcHome $seatDir -Channel 'Jeeves' -Reason 'idle'
        if ($bad2) { throw 'must refuse nick target' }
        $bad3 = Send-WatchIrcBored -IrcHome $seatDir -Channel '#agentic_irc' -Reason 'idle'
        if ($bad3) { throw 'must refuse #agentic_irc' }
    }
    finally { Remove-Item -LiteralPath $seatDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Check 'AM100b open ACK suppresses idle; DONE clears' {
    $seatDir = Join-Path ([IO.Path]::GetTempPath()) ('am100b-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $seatDir | Out-Null
    $out = Join-Path $seatDir 'outbox.txt'
    try {
        @(
            'PRIVMSG #marchhare :ACK FR SimonBarnett/AgentMonitor#100'
        ) | Set-Content -LiteralPath $out -Encoding UTF8
        if (-not (Test-WatchSeatOpenAck -OutboxPath $out -AckStaleMinutes 45)) { throw 'open ACK must be busy' }
        Add-Content -LiteralPath $out -Value 'PRIVMSG #marchhare :DONE FR SimonBarnett/AgentMonitor#100 https://example/pr/1' -Encoding UTF8
        if (Test-WatchSeatOpenAck -OutboxPath $out -AckStaleMinutes 45) { throw 'DONE after ACK must clear busy' }
    }
    finally { Remove-Item -LiteralPath $seatDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Check 'AM100c Sync-WatchBored start then DONE then idle interval' {
    $seatDir = Join-Path ([IO.Path]::GetTempPath()) ('am100c-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $seatDir | Out-Null
    try {
        $st = [pscustomobject]@{ ircHome = $seatDir; ircNick = 'marchhare-31712'; sessionId = 'sid-test' }
        $t0 = [datetime]'2026-09-26T12:00:00'
        $st = Sync-WatchBored -State $st -Mode start -Now $t0
        $lines = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8)
        if ($lines[-1] -ne 'PRIVMSG #marchhare :!bored') { throw "start !bored missing: $($lines[-1])" }
        if (-not $st.boredStartSent) { throw 'boredStartSent not set' }

        # Immediate re-start must not spam
        $n1 = $lines.Count
        $st = Sync-WatchBored -State $st -Mode start -Now $t0.AddSeconds(1)
        $n2 = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8).Count
        if ($n2 -ne $n1) { throw 'second start must not emit another !bored' }

        # Busy open ACK: no idle
        Add-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Value 'PRIVMSG #marchhare :ACK FR x/y#1' -Encoding UTF8
        $st = Sync-WatchBored -State $st -Mode poll -Now $t0.AddMinutes(5)
        $afterBusy = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8)
        if ($afterBusy[-1] -match '!bored') { throw 'must not !bored while open ACK' }

        # DONE -> immediate !bored
        Add-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Value 'PRIVMSG #marchhare :DONE FR x/y#1 https://example/1' -Encoding UTF8
        $tDone = $t0.AddMinutes(6)
        $st = Sync-WatchBored -State $st -Mode poll -Now $tDone
        $afterDone = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8)
        if ($afterDone[-1] -ne 'PRIVMSG #marchhare :!bored') { throw "DONE must emit !bored, got $($afterDone[-1])" }

        # Too soon for idle repeat (< 2 min)
        $nDone = $afterDone.Count
        $st = Sync-WatchBored -State $st -Mode poll -Now $tDone.AddSeconds(60)
        $nSoon = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8).Count
        if ($nSoon -ne $nDone) { throw 'idle must wait ~2 min after DONE !bored' }

        # First idle at 2 min
        $st = Sync-WatchBored -State $st -Mode poll -Now $tDone.AddSeconds(120)
        $afterIdle = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8)
        if ($afterIdle.Count -ne ($nDone + 1)) { throw "expected first idle !bored at 120s; count=$($afterIdle.Count) want $($nDone+1)" }
        if ($afterIdle[-1] -ne 'PRIVMSG #marchhare :!bored') { throw 'idle line wrong' }

        # Repeat needs 3 min
        $nIdle = $afterIdle.Count
        $st = Sync-WatchBored -State $st -Mode poll -Now $tDone.AddSeconds(120 + 120)
        $nMid = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8).Count
        if ($nMid -ne $nIdle) { throw 'idle repeat must wait BoredRepeatSeconds (180)' }
        $st = Sync-WatchBored -State $st -Mode poll -Now $tDone.AddSeconds(120 + 180)
        $nRep = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8).Count
        if ($nRep -ne ($nIdle + 1)) { throw "expected idle repeat; count=$nRep want $($nIdle+1)" }
    }
    finally { Remove-Item -LiteralPath $seatDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Check 'AM100d Get-WatchBoredChannel never bobiverse' {
    $c = Get-WatchBoredChannel -MachineId 'Flamingo'
    if ($c -ne '#flamingo') { throw "got $c" }
    if ($c -match 'bobiverse|agentic_irc|,') { throw "bad channel $c" }
}

Check 'AM100e prompt + loop wire mention monitor !bored' {
    $src = Get-Content -LiteralPath $path -Raw
    if ($src -notmatch 'Sync-WatchBored -State \$state -Mode start') { throw 'must call Sync-WatchBored on start' }
    if ($src -notmatch 'Sync-WatchBored -State \$state -Mode poll') { throw 'must call Sync-WatchBored each poll' }
    if ($src -notmatch 'Monitor posts !bored') { throw 'seed/prompt must mention monitor !bored' }
    if ($src -notmatch 'PRIVMSG #\{machine\} :!bored') { throw 'prompt must document PRIVMSG form' }
    if ($src -notmatch 'Jeeves assignment') { throw 'prompt must say Jeeves assignment = ASSIGN' }
}

Check 'AM100f BoredCheckSeconds <= 5 for DONE latency gate' {
    $src = Get-Content -LiteralPath $path -Raw
    if ($src -notmatch '\[int\]\$BoredCheckSeconds = 5') { throw 'default BoredCheckSeconds must be 5' }
    if ($src -notmatch 'Start-Sleep -Seconds \$boredCheck') { throw 'watch loop must sleep BoredCheckSeconds (not only PollSeconds)' }
    if ($src -notmatch 'Set-WatchBoredActivity') { throw 'forwards must reset idle via Set-WatchBoredActivity' }
}

if ($fail -gt 0) { Write-Host "Test-WatchBored: $fail failed"; exit 1 }
Write-Host 'Test-WatchBored: all passed'
exit 0
