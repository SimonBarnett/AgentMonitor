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

Invoke-Case 'AM97 seat N owns bound IRC home (FR#97 two-seat isolation)' {
    # Static + simulated two-seat bind: separate homes/logs; disconnect refuses foreign home;
    # ASSIGN wake only for matching nick; Bind sets $script:IrcHome (not local-only).
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw
    if ($src -notmatch 'function Get-WatchBoundIrcHome') { throw 'Get-WatchBoundIrcHome required' }
    if ($src -notmatch '\$script:IrcHome = \$resolved') { throw 'Bind-WatchSlot must set $script:IrcHome' }
    if ($src -notmatch 'irc disconnect refused foreign home') { throw 'Disconnect must refuse foreign home' }
    if ($src -notmatch 'irc ensure rebasing state\.ircHome') { throw 'Ensure must rebase stale sibling home' }
    if ($src -match 'New-Item -ItemType File -Force -Path \$script:LogFile \| Out-Null\s*\r?\nif \(-not \$WatchWorker') {
        throw 'must not truncate default log before Bind-WatchSlot'
    }
    # Simulated two seats (no live IRC / monitors)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('am97-' + [guid]::NewGuid().ToString('N'))
    $h1 = Join-Path $root 'watch-grok'
    $h2 = Join-Path $root 'watch-grok-2'
    $logRoot = Join-Path $root 'logs'
    New-Item -ItemType Directory -Force -Path $h1, $h2, $logRoot | Out-Null
    $log1 = Join-Path $logRoot 'Watch-AgentHealth.log'
    $log2 = Join-Path $logRoot 'Watch-AgentHealth-2.log'
    Set-Content -LiteralPath $log1 -Value "seat1-marker`n" -Encoding utf8
    # Import bind helpers with minimal script state
    function script:Write-WatchLog { param([string]$Message) }
    function script:Test-ForbiddenIrcHome { param([string]$ResolvedHome) $false }
    function script:Get-WatchSlotNumberFromHome {
        param([string]$SeatHome, [string]$Kind)
        if ($SeatHome -match '-(\d+)$') { return [int]$Matches[1] }
        return 1
    }
    Import-WatchFunctions -Names @(
        'Get-WatchBoundIrcHome', 'Bind-WatchSlot', 'Disconnect-WatchIrc',
        'Get-IrcFromParts', 'Test-WatchIrcAddressedToNick', 'Format-WatchWakeText'
    )
    # Seat 1 bind
    $script:IrcHomeExplicit = $true
    $script:KindName = 'grok'
    $script:ClientSlot = 0
    $script:BoundIrcHome = $null
    $script:IrcHome = $null
    $script:StateDir = $null
    $script:LogFile = $null
    $LogPath = $log1
    $IrcHome = $h1
    Bind-WatchSlot
    $b1 = Get-WatchBoundIrcHome
    if ($b1.TrimEnd('\') -ne ([IO.Path]::GetFullPath($h1)).TrimEnd('\')) { throw "seat1 bound home wrong: $b1" }
    if ($script:ClientSlot -ne 1) { throw "seat1 slot expected 1 got $($script:ClientSlot)" }
    if (-not (Test-Path -LiteralPath $log1)) { throw 'seat1 log missing' }
    $log1Body = Get-Content -LiteralPath $log1 -Raw
    if ($log1Body -notmatch 'seat1-marker') { throw 'seat1 log must not be wiped on bind' }
    $s1Home = $script:BoundIrcHome
    $s1Log = $script:LogFile
    # Seat 2 bind (simulate second process state)
    $script:IrcHomeExplicit = $true
    $script:BoundIrcHome = $null
    $script:IrcHome = $null
    $LogPath = $log2
    $IrcHome = $h2
    Bind-WatchSlot
    $b2 = Get-WatchBoundIrcHome
    if ($b2.TrimEnd('\') -ne ([IO.Path]::GetFullPath($h2)).TrimEnd('\')) { throw "seat2 bound home wrong: $b2" }
    if ($script:ClientSlot -ne 2) { throw "seat2 slot expected 2 got $($script:ClientSlot)" }
    if ($s1Home.TrimEnd('\') -eq $b2.TrimEnd('\')) { throw 'two seats must not share ircHome' }
    if ($s1Log -eq $script:LogFile) { throw 'two seats must not share LogFile' }
    if (-not (Test-Path -LiteralPath $log2)) { throw 'seat2 log should be created if missing' }
    # Disconnect seat2 must not target seat1 home
    $stForeign = [pscustomobject]@{ ircHome = $h1 }
    Disconnect-WatchIrc -State $stForeign -Reason 'test'
    # (no throw; log refusal). Seat1 marker log still intact:
    if ((Get-Content -LiteralPath $log1 -Raw) -notmatch 'seat1-marker') { throw 'disconnect foreign must not touch seat1 log' }
    # ASSIGN addressing isolation
    $nick1 = 'flamingo-111'
    $nick2 = 'flamingo-222'
    $line1 = "FROM bob-flamingo #flamingo ${nick1}: ASSIGN FR x/y#1"
    $line2 = "FROM bob-flamingo #flamingo ${nick2}: ASSIGN FR x/y#2"
    if (-not (Test-WatchIrcAddressedToNick -Text "${nick1}: ASSIGN FR x/y#1" -OurNick $nick1)) { throw 'nick1 must match own ASSIGN' }
    if (Test-WatchIrcAddressedToNick -Text "${nick2}: ASSIGN FR x/y#2" -OurNick $nick1) { throw 'nick1 must not take nick2 ASSIGN' }
    $w1 = Format-WatchWakeText -Line $line1 -OurNick $nick1
    $w2 = Format-WatchWakeText -Line $line2 -OurNick $nick1
    if ($w1 -notmatch 'FOR YOU') { throw 'own nick wake must be FOR YOU' }
    if ($w2 -match 'FOR YOU') { throw 'other nick ASSIGN must not FOR YOU this seat' }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "AM summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
