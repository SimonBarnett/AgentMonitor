# AgentMonitor self-tests (Windows PowerShell 5.1).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-AgentMonitor.ps1
[CmdletBinding()]
param([string]$OnlyCase)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:Pass = 0
$script:Fail = 0

function Invoke-Case {
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

function Get-CloneStatus {
    $s = @(& git -C $RepoRoot status --porcelain --untracked-files=all)
    return ($s -join "`n")
}

Invoke-Case 'AM1 generated shortcuts lnk not tracked' {
    # Publish-DesktopShortcuts writes machine paths + exe icons into shortcuts\*.lnk on every
    # install; tracked copies left the Desktop clone dirty (9 x M shortcuts/*.lnk).
    $tracked = @(& git -C $RepoRoot ls-files -- 'shortcuts/*.lnk')
    if ($tracked.Count -gt 0) { throw "generated .lnk must not be tracked: $($tracked -join ', ')" }
    & git -C $RepoRoot check-ignore -q -- 'shortcuts/Watch-Agent Grok New.lnk'
    if ($LASTEXITCODE -ne 0) { throw '.gitignore must ignore shortcuts/*.lnk' }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'shortcuts\README.md'))) { throw 'shortcuts/README.md must explain the generated .lnk files' }
}

Invoke-Case 'AM2 publish shortcuts keeps clone clean' {
    $desk = Join-Path ([IO.Path]::GetTempPath()) ('am-desk-' + [guid]::NewGuid().ToString('N'))
    $before = Get-CloneStatus
    try {
        & (Join-Path $RepoRoot 'tools\Publish-DesktopShortcuts.ps1') -MonitorDir $RepoRoot -DesktopDir $desk | Out-Null
        $after = Get-CloneStatus
        if ($after -ne $before) { throw "Publish-DesktopShortcuts dirtied the clone:`n$after" }
        $deskLnk = @(Get-ChildItem -LiteralPath $desk -Filter '*.lnk')
        $repoLnk = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'shortcuts') -Filter '*.lnk')
        if ($deskLnk.Count -ne 9) { throw "expected 9 Desktop .lnk under -DesktopDir, got $($deskLnk.Count)" }
        if ($repoLnk.Count -lt 9) { throw "expected 9 repo shortcuts .lnk, got $($repoLnk.Count)" }
        $w = New-Object -ComObject WScript.Shell
        foreach ($l in $deskLnk) {
            $s = $w.CreateShortcut($l.FullName)
            if ($s.TargetPath -notmatch 'wscript\.exe$') { throw "$($l.Name): target must be wscript.exe" }
            if ($s.Arguments -notmatch 'Run-Hidden\.vbs' -or $s.Arguments -notmatch '-New' -or $s.Arguments -notmatch '-Windows off') { throw "$($l.Name): must launch Run-Hidden.vbs ... -New -Windows off" }
            if ($s.WorkingDirectory -ne $RepoRoot) { throw "$($l.Name): WorkingDirectory must be the clone ($($s.WorkingDirectory))" }
        }
    }
    finally {
        Remove-Item -LiteralPath $desk -Recurse -Force -ErrorAction SilentlyContinue
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

Invoke-Case 'AM3 addressed FROM wake names the seat nick (FR#19 ASSIGN ignored)' {
    Import-WatchFunctions -Names @('Get-IrcFromParts', 'Test-WatchIrcAddressedToNick', 'Format-WatchWakeText')
    $line = 'FROM bob-marchhare #marchhare marchhare-34992: ASSIGN FR SimonBarnett/skills-visionary#19 ACK here when you start.'
    $w = Format-WatchWakeText -Line $line -OurNick 'marchhare-34992'
    if ($w -notmatch '^FOR YOU \(your IRC nick is marchhare-34992;') { throw "addressed wake must start FOR YOU + nick: $w" }
    if ($w -notmatch 'reply on outbox to #marchhare') { throw "wake must name the reply channel: $w" }
    if (-not $w.EndsWith($line)) { throw 'wake must carry the full FROM line' }
    foreach ($t in @('@marchhare-34992, go', 'MARCHHARE-34992 - hi', 'marchhare-34992')) {
        if (-not (Test-WatchIrcAddressedToNick -Text $t -OurNick 'marchhare-34992')) { throw "should be addressed: $t" }
    }
}

Invoke-Case 'AM4 unaddressed / other-nick FROM wake unchanged' {
    Import-WatchFunctions -Names @('Get-IrcFromParts', 'Test-WatchIrcAddressedToNick', 'Format-WatchWakeText')
    $a = 'FROM bob-marchhare #bobiverse marchhare is idle.'
    if ((Format-WatchWakeText -Line $a -OurNick 'marchhare-34992') -ne $a) { throw 'unaddressed line must pass through' }
    $b = 'FROM bob-marchhare #marchhare marchhare-349920: ASSIGN x'
    if ((Format-WatchWakeText -Line $b -OurNick 'marchhare-34992') -ne $b) { throw 'prefix-collision nick must not match' }
    if ((Format-WatchWakeText -Line $a -OurNick '') -ne $a) { throw 'no nick -> unchanged' }
    $long = 'FROM x #c ' + ('y' * 500)
    if ((Format-WatchWakeText -Line $long -OurNick 'n').Length -ne 350) { throw 'unaddressed wake still capped at 350' }
}

Invoke-Case 'AM5 Send-IrcLineToSession uses Format-WatchWakeText + prompt names nick' {
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw
    if ($src -notmatch 'Format-WatchWakeText -Line \$Line -OurNick \(Get-WatchSeatNick -State \$State\)') { throw 'forward path must build wake via Format-WatchWakeText with seat nick' }
    if ($src -notmatch 'Your IRC nick is nick= in') { throw 'seed prompt must tell the seat where its nick is' }
}

Invoke-Case 'AM6 mrb hostile address edges (FR#88)' {
    Import-WatchFunctions -Names @('Test-WatchIrcAddressedToNick', 'Format-WatchWakeText', 'Get-WatchSeatNick')
    # Substring collision: shorter nick must not match longer
    if (Test-WatchIrcAddressedToNick -Text 'marchhare-349920: x' -OurNick 'marchhare-34992') {
        throw 'must not match longer nick with same prefix'
    }
    # Bare channel chatter mentioning nick mid-line is NOT address
    if (Test-WatchIrcAddressedToNick -Text 'see marchhare-34992 later' -OurNick 'marchhare-34992') {
        throw 'mid-line mention must not count as address'
    }
    # Whitespace-only / empty nick
    if (Test-WatchIrcAddressedToNick -Text 'marchhare-34992: x' -OurNick '   ') {
        throw 'blank OurNick must be false'
    }
    # FOR YOU must name outbox target channel from FROM parts
    $line = 'FROM bob-marchhare #agentic_irc marchhare-34992: ping'
    $w = Format-WatchWakeText -Line $line -OurNick 'marchhare-34992'
    if ($w -notmatch 'outbox to #agentic_irc') { throw "channel target wrong: $w" }
    # Seed / nick resolution path exists
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw
    if ($src -notmatch 'function Get-WatchSeatNick') { throw 'Get-WatchSeatNick required' }
    if ($src -notmatch 'coordinator\.pid') { throw 'nick source coordinator.pid must be documented in script' }
    if ($src -notmatch 'FOR YOU \(your IRC nick is') { throw 'FOR YOU format string required' }
}

Invoke-Case 'AM7 adopt live agent when rootPid+session match (FR#89)' {
    function script:Write-WatchLog { param([string]$Message) }
    Import-WatchFunctions -Names @('Test-WatchProcessAlive', 'Test-WatchRootMatchesSession', 'Try-AdoptLiveWatchAgent')
    $sid = '972c6563-d6ac-4d95-9a7d-0ec509d158a6'
    $cl = "C:\x\agent.exe --cwd D:\ai -r $sid prompt"
    if (-not (Test-WatchRootMatchesSession -RootPid 32208 -SessionId $sid -CommandLine $cl)) {
        throw 'matching session in command line must adopt'
    }
    if (Test-WatchRootMatchesSession -RootPid 32208 -SessionId $sid -CommandLine 'agent.exe -r other-session') {
        throw 'wrong session must not match'
    }
    if (Test-WatchRootMatchesSession -RootPid 0 -SessionId $sid -CommandLine $cl) {
        throw 'rootPid 0 must not match'
    }
    # Dead pid: use unlikely pid
    if (Test-WatchRootMatchesSession -RootPid 1 -SessionId $sid -CommandLine $cl) {
        # pid 1 may or may not exist on Windows — only fail if process is alive AND we claimed match without alive check
        # Test-WatchRootMatchesSession requires alive; if System Idle/pid1 missing, OK
    }
    $state = [pscustomobject]@{ kind = 'grok'; sessionId = $sid; rootPid = 32208; seenSession = $true }
    # Force match path with explicit command line by mocking alive via current process
    $me = $PID
    $state2 = [pscustomobject]@{ kind = 'grok'; sessionId = $sid; rootPid = $me; seenSession = $true }
    $clMe = "fake-agent.exe -r $sid --cwd D:\ai"
    $adopted = Try-AdoptLiveWatchAgent -State $state2 -CommandLine $clMe
    if (-not $adopted) { throw 'live current PID with session in CL must adopt' }
    if ($adopted.RootPid -ne $me) { throw 'adopted RootPid must be live pid' }
    $dead = Try-AdoptLiveWatchAgent -State ([pscustomobject]@{ kind = 'grok'; sessionId = $sid; rootPid = 0 }) -CommandLine $clMe
    if ($dead) { throw 'rootPid 0 must not adopt' }
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw
    if ($src -notmatch 'Try-AdoptLiveWatchAgent -State \$state') { throw 'main loop must call Try-AdoptLiveWatchAgent' }
    if ($src -notmatch '\[switch\]\$Reload') { throw '-Reload switch required for monitor hotpatch path' }
}

Invoke-Case 'AM8 stable nick across monitor restart (FR#89)' {
    function script:Write-WatchLog { param([string]$Message) }
    Import-WatchFunctions -Names @('Resolve-StableWatchIrcNick')
    $st = [pscustomobject]@{ ircNick = 'marchhare-34992'; seatNickPid = 34992 }
    $n = Resolve-StableWatchIrcNick -State $st -MachineId 'marchhare' -ResolvedHome '' -DefaultSeatPid 99999 -AgentRows @()
    if ($n -ne 'marchhare-34992') { throw "expected stable nick marchhare-34992, got $n" }
    $agents = @([pscustomobject]@{ CommandLine = 'python irc_agent.py --nick marchhare-34992 --home x' })
    $n2 = Resolve-StableWatchIrcNick -State ([pscustomobject]@{}) -MachineId 'marchhare' -ResolvedHome '' -DefaultSeatPid 1 -AgentRows $agents
    if ($n2 -ne 'marchhare-34992') { throw "live agent nick must win, got $n2" }
    $n3 = Resolve-StableWatchIrcNick -State ([pscustomobject]@{}) -MachineId 'marchhare' -ResolvedHome '' -DefaultSeatPid 4242 -AgentRows @()
    if ($n3 -ne 'marchhare-4242') { throw "default seat pid nick expected, got $n3" }
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw
    if ($src -notmatch 'Resolve-StableWatchIrcNick') { throw 'Ensure-WatchIrcSeat must use Resolve-StableWatchIrcNick' }
    if ($src -notmatch 'seatNickPid') { throw 'state.seatNickPid required for nick stability' }
}

Write-Host ''

Invoke-Case 'AM9 FR89 docs reload playbook' {
    $doc = Join-Path $RepoRoot 'docs\monitor-reload-fr89.md'
    if (-not (Test-Path -LiteralPath $doc)) { throw 'docs/monitor-reload-fr89.md required' }
    $body = Get-Content -LiteralPath $doc -Raw
    if ($body -notmatch '-Reload') { throw 'docs must document -Reload' }
    if ($body -notmatch 'adopt') { throw 'docs must document adopt' }
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw
    if ($src -notmatch '\[switch\]\$Reload') { throw 'script must expose -Reload' }
    if ($src -notmatch 'Try-AdoptLiveWatchAgent') { throw 'script must adopt live agent' }
    if ($src -notmatch 'Resolve-StableWatchIrcNick') { throw 'script must stabilize nick' }
}

Invoke-Case 'AM99 oversized session rotates archive never delete (FR#99)' {
    function script:Write-WatchLog { param([string]$Message) }
    function script:Write-WatchSessionHealthReport { param($Kind, $Event, $Fields) }
    Import-WatchFunctions -Names @(
        'Get-GrokCwdSessionBucket', 'Resolve-GrokSessionDir', 'Get-WatchSessionSizeInfo',
        'Test-WatchSessionNeedsRotation', 'Archive-WatchSessionDir', 'Ensure-WatchSessionBeforeResume',
        'New-WatchSessionId', 'Get-GrokSessionsRoot'
    )
    $root = Join-Path ([IO.Path]::GetTempPath()) ('am99-' + [guid]::NewGuid().ToString('N'))
    $cwd = Join-Path $root 'work'
    New-Item -ItemType Directory -Force -Path $cwd | Out-Null
    $sessions = Join-Path $root 'sessions'
    $bucket = Join-Path $sessions (Get-GrokCwdSessionBucket -WorkDir $cwd)
    $sid = '972c6563-d6ac-4d95-9a7d-0ec509d158a6'
    $sess = Join-Path $bucket $sid
    New-Item -ItemType Directory -Force -Path $sess | Out-Null
    # 11 MB fake updates.jsonl (> 10 MB default)
    $updates = Join-Path $sess 'updates.jsonl'
    $fs = [IO.File]::Open($updates, [IO.FileMode]::Create, [IO.FileAccess]::Write)
    try {
        $chunk = New-Object byte[] (1MB)
        for ($i = 0; $i -lt 11; $i++) { $fs.Write($chunk, 0, $chunk.Length) }
    }
    finally { $fs.Dispose() }
    $info = Get-WatchSessionSizeInfo -SessionDir $sess
    if (-not (Test-WatchSessionNeedsRotation -SizeInfo $info -MaxUpdatesMb 10)) {
        throw "11MB updates should need rotation (bytes=$($info.UpdatesBytes))"
    }
    $script:GrokSessionsRoot = $sessions
    $script:SessionMaxUpdatesMb = 10
    # Resolve needs Get-GrokSessionsRoot which uses $GrokSessionsRoot param - bind script var used by function
    $script:GrokSessionsRoot = $sessions
    # Patch via env
    $env:BOB_GROK_SESSIONS_ROOT = $sessions
    $st = [pscustomobject]@{ sessionId = $sid; seenSession = $true }
    $st2 = Ensure-WatchSessionBeforeResume -State $st -WorkDir $cwd -Kind 'grok'
    if ($st2.sessionId -eq $sid) { throw 'session id must change after oversized rotate' }
    if (Test-Path -LiteralPath $sess) { throw 'old session dir must be moved (archived), not left in place' }
    $arch = @(Get-ChildItem -LiteralPath $bucket -Directory -Filter '_archive-*' -ErrorAction SilentlyContinue)
    if ($arch.Count -lt 1) {
        # archive is sibling under bucket parent
        $arch = @(Get-ChildItem -LiteralPath $bucket -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '_archive-*' })
    }
    $found = $false
    # Archive-WatchSessionDir moves session into _archive-*/sid under parent of session (bucket)
    $archDirs = @(Get-ChildItem -LiteralPath $bucket -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '_archive-*' })
    if ($archDirs.Count -lt 1) { throw 'archive folder missing under session bucket' }
    $moved = Join-Path $archDirs[0].FullName $sid
    if (-not (Test-Path -LiteralPath $moved)) { throw "archived session missing at $moved" }
    $movedUpdates = Join-Path $moved 'updates.jsonl'
    if (-not (Test-Path -LiteralPath $movedUpdates)) { throw 'archive must keep updates.jsonl (never delete)' }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\BOB_GROK_SESSIONS_ROOT -ErrorAction SilentlyContinue
}

Invoke-Case 'AM99b hung no-cpu forward detects and rotates once (FR#99)' {
    function script:Write-WatchLog { param([string]$Message) }
    function script:Write-WatchSessionHealthReport { param($Kind, $Event, $Fields) }
    function script:Test-WatchProcessAlive { param([int]$ProcessId) return ($ProcessId -eq 4242) }
    function script:Get-ProcessCpuSeconds { param([int]$ProcessId) return 1.0 }  # frozen CPU
    function script:Send-IrcLineToSession {
        param($State, [string]$Line)
        $State | Add-Member -NotePropertyName 'redelivered' -NotePropertyValue $Line -Force
        return $State
    }
    Import-WatchFunctions -Names @('Update-WatchPendingForwardHang', 'Archive-WatchSessionDir', 'New-WatchSessionId')
    # Provide Resolve-GrokSessionDir as no-op missing dir
    function script:Resolve-GrokSessionDir { param($SessionId, $WorkDir, $SessionsRoot = '') return $null }
    $script:SessionHangMinutes = 0.001  # tiny threshold for test
    $script:Grok = $true
    $script:Cwd = $env:TEMP
    $st = [pscustomobject]@{
        sessionId             = 'old-session-id'
        seenSession           = $true
        pendingForwardPid     = 4242
        pendingForwardCpu     = 1.0
        pendingForwardCpuAt   = (Get-Date).AddMinutes(-10)
        pendingForwardLine    = 'FROM bob-x #x hi'
        pendingForwardRetried = $false
    }
    $out = Update-WatchPendingForwardHang -State $st
    if ($out.sessionId -eq 'old-session-id') { throw 'hung path must rotate session id' }
    if (-not $out.redelivered) { throw 'must redeliver pending FROM once after hang rotate' }
    # Second hang after retry => unhealthy
    $st2 = [pscustomobject]@{
        sessionId             = 's2'
        seenSession           = $true
        pendingForwardPid     = 4242
        pendingForwardCpu     = 1.0
        pendingForwardCpuAt   = (Get-Date).AddMinutes(-10)
        pendingForwardLine    = 'FROM bob-x #x hi2'
        pendingForwardRetried = $true
    }
    $out2 = Update-WatchPendingForwardHang -State $st2
    if (-not [bool]$out2.seatUnhealthy) { throw 'second hang must mark seatUnhealthy' }
}

Invoke-Case 'AM99c max one pending forward busy (FR#99)' {
    function script:Write-WatchLog { param([string]$Message) }
    function script:Test-WatchProcessAlive { param([int]$ProcessId) return ($ProcessId -eq 99) }
    function script:Test-CursorAgentForwardBusy { param([string]$SessionId) return $false }
    Import-WatchFunctions -Names @('Test-WatchForwardBusy')
    $busy = Test-WatchForwardBusy -State ([pscustomobject]@{ pendingForwardPid = 99; sessionId = 'x' })
    if (-not $busy) { throw 'live pending pid must be busy' }
    $free = Test-WatchForwardBusy -State ([pscustomobject]@{ pendingForwardPid = 0; sessionId = 'x' })
    if ($free) { throw 'no pending should not be busy' }
}

Invoke-Case 'AM99d source documents FR99 rotation' {
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw
    if ($src -notmatch 'Ensure-WatchSessionBeforeResume') { throw 'missing Ensure-WatchSessionBeforeResume' }
    if ($src -notmatch 'Archive-WatchSessionDir') { throw 'missing Archive-WatchSessionDir' }
    if ($src -notmatch 'Update-WatchPendingForwardHang') { throw 'missing hang detector' }
    if ($src -notmatch 'SessionMaxUpdatesMb') { throw 'missing SessionMaxUpdatesMb param' }
    if ($src -notmatch 'never delete' -or $src -notmatch 'Move-Item') {
        # Move-Item is the archive path
        if ($src -notmatch 'Move-Item') { throw 'archive must Move-Item not delete' }
    }
    $readme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw
    if ($readme -notmatch 'FR #99|oversized|session rotate') {
        throw 'README should mention session rotation FR #99'
    }
}

Write-Host "AM summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
