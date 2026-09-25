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

Write-Host ''
Write-Host "AM summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
