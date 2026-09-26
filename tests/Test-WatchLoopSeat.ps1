# FR #103: loop seat / -NoBored opt-out from fleet !bored + ACK/DONE brief.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchLoopSeat.ps1
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

foreach ($n in @(
        'Get-WatchSeatChannels',
        'Test-WatchWorkerNickGrammar',
        'Get-WatchOutboxPayload',
        'Get-WatchOutboxRows',
        'Test-WatchSeatOpenAck',
        'Get-WatchBoredChannel',
        'Send-WatchIrcBored',
        'Get-WatchOutboxDoneKey',
        'Test-WatchSeatBoredBusy',
        'Get-WatchSeatNick',
        'Sync-WatchBored',
        'Get-AgentPrompt',
        'Get-CursorSeedPrompt',
        'Get-GrokRules',
        'Test-WatchNoBored'
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
$script:WatchChannelOverride = $null
$script:WatchNickOverride = $null
$script:NoBored = $false
$script:SeatType = 'fleet'

Check 'AM103a loop Sync-WatchBored never emits' {
    $script:NoBored = $true
    $script:WatchChannelOverride = '#ce-priority-dev1'
    $script:WatchNickOverride = 'dayworks-dev1'
    $seatDir = Join-Path ([IO.Path]::GetTempPath()) ('am103a-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $seatDir | Out-Null
    try {
        $st = [pscustomobject]@{ ircHome = $seatDir; ircNick = 'dayworks-dev1'; sessionId = 'sid-loop' }
        $t0 = [datetime]'2026-09-26T12:00:00'
        $st = Sync-WatchBored -State $st -Mode start -Now $t0
        if (Test-Path -LiteralPath (Join-Path $seatDir 'outbox.txt')) {
            $n = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8 | Where-Object { $_ -match '!bored' }).Count
            if ($n -gt 0) { throw 'start must not !bored on loop seat' }
        }
        Add-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Value 'PRIVMSG #ce-priority-dev1 :[dayworks] done something' -Encoding UTF8
        $st = Sync-WatchBored -State $st -Mode poll -Now $t0.AddMinutes(10)
        $bored = @(Get-Content -LiteralPath (Join-Path $seatDir 'outbox.txt') -Encoding UTF8 | Where-Object { $_ -match '!bored' })
        if ($bored.Count -gt 0) { throw 'idle/DONE path must not !bored on loop seat' }
    }
    finally {
        Remove-Item -LiteralPath $seatDir -Recurse -Force -ErrorAction SilentlyContinue
        $script:NoBored = $false
        $script:WatchChannelOverride = $null
        $script:WatchNickOverride = $null
    }
}

Check 'AM103b loop prompt has no ASSIGN/ACK/!bored claim path' {
    $script:NoBored = $true
    $script:WatchChannelOverride = '#ce-priority-dev1'
    $script:WatchNickOverride = 'dayworks-dev1'
    try {
        $p = Get-AgentPrompt -ResolvedIrcHome 'C:\tmp\loop-home'
        if ($p -match '(?i)Monitor posts !bored') { throw 'loop prompt must not say monitor posts !bored' }
        if ($p -match '(?i)treat a Jeeves') { throw 'loop prompt must not treat Jeeves as ASSIGN' }
        if ($p -match '(?i)\bASSIGN\b') { throw 'loop prompt must not mention ASSIGN' }
        if ($p -match '(?i)Jeeves assignment') { throw 'loop prompt must not mention Jeeves assignment' }
        if ($p -notmatch '(?i)never post !bored') { throw 'loop prompt must forbid !bored' }
        if ($p -notmatch '(?i)never ACK') { throw 'loop prompt must forbid ACK to Jeeves' }
        if ($p -notmatch 'continuous loop agent' -and $p -notmatch 'NOT a fleet') { throw 'loop prompt must identify loop seat' }
        $seed = Get-CursorSeedPrompt -ResolvedIrcHome 'C:\tmp\loop-home'
        if ($seed -match '(?i)Monitor posts !bored') { throw 'loop seed must not say monitor posts !bored' }
        if ($seed -notmatch '(?i)No !bored') { throw 'loop seed must say No !bored' }
        $rules = Get-GrokRules
        if ($rules -match '(?i)treat Jeeves assignment') { throw 'loop grok rules must not say treat Jeeves as ASSIGN' }
    }
    finally {
        $script:NoBored = $false
        $script:WatchChannelOverride = $null
        $script:WatchNickOverride = $null
    }
}

Check 'AM103c Get-WatchSeatChannels respects -Channel override' {
    $script:WatchChannelOverride = '#ce-priority-dev1'
    try {
        $c = Get-WatchSeatChannels -MachineId 'marchhare'
        if ($c -ne '#ce-priority-dev1') { throw "got $c" }
        if ($c -match 'bobiverse|agentic_irc|,') { throw "bad $c" }
    }
    finally { $script:WatchChannelOverride = $null }
    $fleet = Get-WatchSeatChannels -MachineId 'marchhare'
    if ($fleet -ne '#marchhare') { throw "fleet channel broken: $fleet" }
}

Check 'AM103d worker nick grammar helper' {
    if (-not (Test-WatchWorkerNickGrammar -Nick 'marchhare-31712')) { throw 'machine-pid must match worker grammar' }
    if (Test-WatchWorkerNickGrammar -Nick 'dayworks-dev1') { throw 'dayworks-dev1 must NOT match worker grammar' }
    if (Test-WatchWorkerNickGrammar -Nick 'dayworks') { throw 'plain nick must not match' }
}

Check 'AM103e default fleet prompt still has !bored + Jeeves assignment' {
    $script:NoBored = $false
    $script:WatchChannelOverride = $null
    $script:WatchNickOverride = $null
    $p = Get-AgentPrompt -ResolvedIrcHome 'C:\tmp\fleet-home'
    if ($p -notmatch '(?i)!bored') { throw 'fleet prompt must document monitor !bored' }
    if ($p -notmatch '(?i)Jeeves assignment') { throw 'fleet prompt must document Jeeves assignment' }
    if ($p -notmatch '(?i)\bACK\b') { throw 'fleet prompt must mention ACK' }
}

Check 'AM103f param + Sync-WatchBored NoBored gate in source' {
    $src = Get-Content -LiteralPath $path -Raw
    if ($src -notmatch '\[ValidateSet\(''fleet'', ''loop''\)\]') { throw 'must have -SeatType fleet|loop' }
    if ($src -notmatch '\[switch\]\$NoBored') { throw 'must have -NoBored' }
    if ($src -notmatch '\[string\]\$Channel') { throw 'must have -Channel' }
    if ($src -notmatch '\[string\]\$Nick') { throw 'must have -Nick' }
    if ($src -notmatch 'if \(Test-WatchNoBored\)') { throw 'Sync-WatchBored must gate on Test-WatchNoBored' }
    if ($src -notmatch 'looks like a worker') { throw 'must reject worker-grammar -Nick for loop' }
}

if ($fail -gt 0) { Write-Host "Test-WatchLoopSeat: $fail failed"; exit 1 }
Write-Host 'Test-WatchLoopSeat: all passed'
exit 0
