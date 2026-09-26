# FR #104: wake prompt documents exact ACK/DONE wire (no nick prefix; append-only).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchAckDoneWire.ps1
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

foreach ($n in @('Get-AgentPrompt', 'Get-CursorSeedPrompt', 'Format-WatchWakeText', 'Test-WatchNoBored', 'Get-IrcFromParts', 'Test-WatchIrcAddressedToNick')) {
    . ([scriptblock]::Create((Get-Fn $n).Extent.Text))
}
$script:NoBored = $false
$script:WatchChannelOverride = $null
$script:WatchNickOverride = $null

Check 'AM104a fleet prompt has ACK and DONE format strings' {
    $p = Get-AgentPrompt -ResolvedIrcHome 'C:\tmp\watch-home'
    if ($p -notmatch 'ACK <FR\|MRB\|UAT> <owner/repo>#<n>') { throw 'missing ACK format' }
    if ($p -notmatch 'DONE <FR\|MRB\|UAT> <owner/repo>#<n> \[PASS\|FAIL\] <PR-url>') { throw 'missing DONE format' }
    if ($p -notmatch 'no nick: prefix' -and $p -notmatch 'No nick: prefix' -and $p -notmatch 'no nick prefix') {
        throw 'must state no nick prefix rule'
    }
    if ($p -notmatch 'Nothing after the URL' -and $p -notmatch 'nothing after URL' -and $p -notmatch 'ends at URL') {
        throw 'must say DONE ends at URL'
    }
    if ($p -notmatch 'APPEND only' -and $p -notmatch 'Append only' -and $p -notmatch 'append only') {
        throw 'must require append-only outbox'
    }
    if ($p -match '(?i)marchhare ACK #' -or $p -match '(?i)nick-first ACK') {
        throw 'must not teach nick-first ACK'
    }
}

Check 'AM104b FOR YOU wake reminds no nick prefix' {
    function Get-IrcFromParts { param([string]$Line)
        return [pscustomobject]@{ target = '#marchhare'; text = 'marchhare-1: FR SimonBarnett/x#1 https://x'; nick = 'Jeeves' }
    }
    function Test-WatchIrcAddressedToNick { param([string]$Text, [string]$OurNick) return $true }
    $w = Format-WatchWakeText -Line 'FROM Jeeves #marchhare :marchhare-1: FR x/y#1 https://z' -OurNick 'marchhare-1'
    if ($w -notmatch 'no marchhare-1: prefix' -and $w -notmatch 'no \{0\}: prefix' -and $w -notmatch 'no nick') {
        # Format uses -f with OurNick in "no {0}: prefix"
        if ($w -notmatch 'no .+?: prefix') { throw "wake missing no-prefix reminder: $w" }
    }
    if ($w -notmatch 'ACK or DONE') { throw 'wake must mention ACK or DONE' }
    if ($w -notmatch 'append PRIVMSG only' -and $w -notmatch 'append') { throw 'wake must mention append' }
}

Check 'AM104c loop prompt still forbids ACK/DONE' {
    $script:NoBored = $true
    $script:WatchChannelOverride = '#ce-priority-dev1'
    $script:WatchNickOverride = 'dayworks-dev1'
    try {
        $p = Get-AgentPrompt -ResolvedIrcHome 'C:\tmp\loop'
        if ($p -notmatch '(?i)never ACK') { throw 'loop must forbid ACK' }
        if ($p -match 'ACK <FR\|MRB\|UAT>') { throw 'loop must not teach fleet ACK format' }
    }
    finally {
        $script:NoBored = $false
        $script:WatchChannelOverride = $null
        $script:WatchNickOverride = $null
    }
}

Check 'AM104d skills document wire' {
    $skill = Get-Content -LiteralPath (Join-Path $RepoRoot '.grok\skills\watch-seat\SKILL.md') -Raw
    if ($skill -notmatch 'ACK <FR\|MRB\|UAT>') { throw 'watch-seat missing ACK format' }
    if ($skill -notmatch 'DONE <FR\|MRB\|UAT>') { throw 'watch-seat missing DONE format' }
    if ($skill -notmatch '(?i)No nick prefix') { throw 'watch-seat missing no nick prefix' }
    if ($skill -notmatch '(?i)Append') { throw 'watch-seat missing append rule' }
}

if ($fail -gt 0) { Write-Host "Test-WatchAckDoneWire: $fail failed"; exit 1 }
Write-Host 'Test-WatchAckDoneWire: all passed'
exit 0
