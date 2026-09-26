# FR #126: root/console exit → QUIT, stop IRC children, no !bored/wakes, monitor exits (no relaunch).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchRootExit.ps1
[CmdletBinding()]
param([string]$OnlyCase)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:Pass = 0
$script:Fail = 0

function Check {
    param([string]$Id, [scriptblock]$Body)
    if ($OnlyCase -and $Id -ne $OnlyCase) { return }
    try {
        & $Body
        $script:Pass++
        Write-Host "PASS $Id"
    }
    catch {
        $script:Fail++
        Write-Host "FAIL $Id :: $($_.Exception.Message)"
    }
}

function Import-WatchFunctions {
    param([string[]]$Names)
    $path = Join-Path $RepoRoot 'Watch-AgentHealth.ps1'
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    foreach ($n in $Names) {
        $fn = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $n }, $true)
        if (-not $fn) { throw "function $n missing from Watch-AgentHealth.ps1" }
        . ([scriptblock]::Create($fn.Extent.Text))
        Set-Item -Path ("function:script:" + $n) -Value (Get-Item ("function:" + $n)).ScriptBlock
    }
}

Check 'AM126a source: grok unhealthy tears down and breaks (no needStart relaunch)' {
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw -Encoding UTF8
    if ($src -notmatch 'function Complete-WatchSeatRootExit') { throw 'Complete-WatchSeatRootExit missing' }
    if ($src -notmatch 'function Test-WatchSeatRootGone') { throw 'Test-WatchSeatRootGone missing' }
    if ($src -notmatch 'root exit teardown \(no restart\)') { throw 'grok unhealthy must log no-restart teardown' }
    if ($src -match 'unhealthy agent tree rootPid=\$\(\$current\.RootPid\) - restart') {
        throw 'grok unhealthy must not restart the agent tree'
    }
    # After unhealthy / cursor tui-gone, loop must break (monitor exit), not needStart=$true.
    if ($src -notmatch 'Complete-WatchSeatRootExit[\s\S]{0,200}break') {
        throw 'root exit path must break out of the watch loop'
    }
    if ($src -notmatch 'seat root gone - monitor exit') {
        throw 'monitor exit log line missing'
    }
}

Check 'AM126b Complete-WatchSeatRootExit writes quit.req on own home; skips foreign' {
    Import-WatchFunctions -Names @(
        'Test-WatchSeatRootGone',
        'Clear-WatchWakeState',
        'Complete-WatchSeatRootExit'
    )
    # Stub Disconnect / Stop so unit test does not touch live IRC.
    $script:DisconnectCalls = @()
    $script:StopTreeCalls = @()
    function script:Disconnect-WatchIrc {
        param($State, [string]$Reason = '')
        $script:DisconnectCalls += ,[pscustomobject]@{ Home = [string]$State.ircHome; Reason = $Reason }
        $resolved = [IO.Path]::GetFullPath([string]$State.ircHome)
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText((Join-Path $resolved 'quit.req'), $Reason, $utf8)
    }
    function script:Stop-WatchedTree {
        param([int]$RootPid)
        $script:StopTreeCalls += ,$RootPid
    }
    function script:Write-WatchLog { param([string]$Message) }

    $seatDir = Join-Path ([IO.Path]::GetTempPath()) ('am126-home-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $seatDir | Out-Null
    try {
        $st = [pscustomobject]@{
            ircHome         = $seatDir
            rootPid         = 4242
            wakePid         = 0
            wakeQueue       = @('FROM bob #x hello')
            sessionId       = 'sess-126'
            seatRootGone    = $false
        }
        $out = Complete-WatchSeatRootExit -State $st -RootPid 4242 -Reason 'tui closed'
        if (-not (Test-WatchSeatRootGone -State $out)) { throw 'seatRootGone not set' }
        if (-not [bool]$out.seatUnhealthy) { throw 'seatUnhealthy not set' }
        if ([int]$out.rootPid -ne 0) { throw 'rootPid must be 0' }
        $q = @($out.wakeQueue)
        if ($q.Count -ne 0) { throw 'wakeQueue must be cleared' }
        $quit = Join-Path $seatDir 'quit.req'
        if (-not (Test-Path -LiteralPath $quit)) { throw 'quit.req missing' }
        $body = [IO.File]::ReadAllText($quit)
        if ($body -notmatch 'tui closed') { throw "quit.req body wrong: $body" }
        if ($script:DisconnectCalls.Count -ne 1) { throw 'Disconnect-WatchIrc once' }
        if ($script:StopTreeCalls.Count -ne 1 -or $script:StopTreeCalls[0] -ne 4242) {
            throw 'Stop-WatchedTree must target root only'
        }
        # Idempotent second call
        $out2 = Complete-WatchSeatRootExit -State $out -RootPid 99 -Reason 'again'
        if ($script:DisconnectCalls.Count -ne 1) { throw 'second Complete must no-op Disconnect' }
        if ($script:StopTreeCalls.Count -ne 1) { throw 'second Complete must no-op Stop tree' }
    }
    finally {
        Remove-Item -LiteralPath $seatDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Check 'AM126c Sync-WatchBored skips when seatRootGone' {
    Import-WatchFunctions -Names @('Test-WatchSeatRootGone', 'Sync-WatchBored')
    function script:Test-WatchNoBored { return $false }
    function script:Write-WatchLog { param([string]$Message) }
    $seatDir = Join-Path ([IO.Path]::GetTempPath()) ('am126-bored-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $seatDir | Out-Null
    try {
        $outbox = Join-Path $seatDir 'outbox.txt'
        [IO.File]::WriteAllText($outbox, '', (New-Object System.Text.UTF8Encoding $false))
        $st = [pscustomobject]@{
            ircHome      = $seatDir
            seatRootGone = $true
            boredStartSent = $false
        }
        $before = (Get-Item -LiteralPath $outbox).Length
        $null = Sync-WatchBored -State $st -Mode poll
        $after = (Get-Item -LiteralPath $outbox).Length
        if ($after -ne $before) { throw 'must not append !bored when seatRootGone' }
        $text = [IO.File]::ReadAllText($outbox)
        if ($text -match '!bored') { throw 'outbox must not contain !bored' }
    }
    finally {
        Remove-Item -LiteralPath $seatDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Check 'AM126d Sync-WatchWakeLifecycle StartNext no-ops when seatRootGone' {
    Import-WatchFunctions -Names @('Test-WatchSeatRootGone', 'Sync-WatchWakeLifecycle', 'Clear-WatchWakeState', 'Pop-WatchWakeQueue')
    function script:Write-WatchLog { param([string]$Message) }
    function script:Write-WatchSeatTranscript { param([string]$Message) }
    function script:Test-WatchProcessAlive { param([int]$ProcessId) return $false }
    function script:Test-WatchWakeInFlight { param($State) return $false }
    function script:Send-IrcLineToSession { param($State, [string]$Line) throw 'must not start wake when seatRootGone' }
    $st = [pscustomobject]@{
        seatRootGone   = $true
        wakePid        = 0
        wakeQueue      = @('FROM jeeves #ionos ionos-1: ping')
        sessionId      = 's'
    }
    $out = Sync-WatchWakeLifecycle -State $st -StartNext
    if (@($out.wakeQueue).Count -ne 1) { throw 'queue must remain untouched when root gone' }
}

Check 'AM126e docs park issue 126' {
    $fr = Join-Path $RepoRoot 'docs\feature-request-root-exit-teardown-2026-09-26.md'
    $plan = Join-Path $RepoRoot 'docs\build-and-test-plan-root-exit-teardown-2026-09-26.md'
    if (-not (Test-Path -LiteralPath $fr)) { throw 'FR markdown missing' }
    if (-not (Test-Path -LiteralPath $plan)) { throw 'build plan missing' }
    $frText = Get-Content -LiteralPath $fr -Raw
    if ($frText -notmatch 'issues/126') { throw 'FR must link issue 126' }
    if ($frText -notmatch 'quit\.req') { throw 'FR must mention quit.req' }
}

Check 'AM126f source: Cursor TUI-gone uses Complete-WatchSeatRootExit + break' {
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw -Encoding UTF8
    if ($src -notmatch 'root exit teardown \(FR#126\)') {
        throw 'Cursor TUI-gone must log FR#126 root exit teardown'
    }
    if ($src -notmatch '(?s)root exit teardown \(FR#126\).{0,250}Complete-WatchSeatRootExit.{0,200}\bbreak\b') {
        throw 'Cursor TUI-gone must Complete-WatchSeatRootExit then break'
    }
    if ($src -notmatch 'irc disconnect refused foreign home') {
        throw 'Disconnect must refuse foreign homes (slot isolation A5)'
    }
}

Check 'AM126g source: forward and IRC reconnect gated on seatRootGone' {
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw -Encoding UTF8
    if ($src -notmatch 'forward skipped \(seat root gone\)') {
        throw 'Send-IrcLineToSession must skip wakes when seatRootGone'
    }
    if ($src -notmatch 'Test-WatchSeatRootGone -State \$state\) -or \(\$Cursor') {
        throw 'Ensure-WatchIrcSeat skipIrc must include Test-WatchSeatRootGone'
    }
    if ($src -notmatch 'orphan watcher after root/console loss must never post !bored') {
        throw 'Sync-WatchBored must document/gate seatRootGone'
    }
}

Write-Host ("Summary PASS={0} FAIL={1}" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
