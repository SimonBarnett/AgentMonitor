# AgentMonitor #136: never keep dead nick suffix; prefer live rootPid; write seat= before agent start.
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
    if (-not $f) { throw "function $Name missing" }
    return $f
}

foreach ($n in @('Resolve-WatchSeatPid', 'Resolve-StableWatchIrcNick', 'Test-WatchProcessAlive')) {
    . ([scriptblock]::Create((Get-Fn $n).Extent.Text))
}

Check 'AM136a dead nick suffix dropped for live rootPid' {
    function Write-WatchLog { param([string]$Message) }
    $live = $PID
    $st = [pscustomobject]@{
        ircNick     = 'marchhare-31712'
        seatNickPid = 31712
        rootPid     = $live
    }
    $n = Resolve-StableWatchIrcNick -State $st -MachineId 'marchhare' -ResolvedHome '' -DefaultSeatPid 1 -AgentRows @()
    if ($n -ne ("marchhare-{0}" -f $live)) { throw "want marchhare-$live got $n" }
}

Check 'AM136b Resolve-WatchSeatPid prefers live rootPid' {
    $live = $PID
    $st = [pscustomobject]@{ rootPid = $live }
    $got = Resolve-WatchSeatPid -CoordPath '' -Default 1 -State $st
    if ($got -ne $live) { throw "want $live got $got" }
}

Check 'AM136c Ensure writes coordinator before start agent' {
    $src = Get-Content -LiteralPath $path -Raw
    if ($src -notmatch 'Write coordinator BEFORE starting irc_agent') {
        throw 'Ensure must document pre-write of coordinator.pid'
    }
    if ($src -notmatch 'irc ensure re-nick to') {
        throw 'Ensure must re-nick when suffix pid is dead'
    }
    # Ordering: Set-Content coordinator then start agent
    $iCoord = $src.IndexOf('Write coordinator BEFORE starting irc_agent')
    $iStart = $src.IndexOf('irc ensure start agent nick=')
    if ($iCoord -lt 0 -or $iStart -lt 0 -or $iCoord -gt $iStart) {
        throw 'coordinator pre-write must appear before start agent log'
    }
}

if ($fail -gt 0) { Write-Host "Test-WatchSeatEndedNick: $fail failed"; exit 1 }
Write-Host 'Test-WatchSeatEndedNick: all passed'
exit 0

