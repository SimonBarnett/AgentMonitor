# AM10 CAST IRON (Simon 2026-09-25): worker / watch seats JOIN their own #{machine} ONLY.
# flamingo-46804 was launched with --channel #bobiverse,#flamingo,#agentic_irc.
# #bobiverse is for bob-{machine} ears, Jeeves and humans only.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WorkerSeatChannel.ps1
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

Check 'AM10a Get-WatchSeatChannels = own #machine only' {
    . ([scriptblock]::Create((Get-Fn 'Get-WatchSeatChannels').Extent.Text))
    $cases = @{ 'flamingo' = '#flamingo'; 'MarchHare' = '#marchhare'; ' #Flamingo ' = '#flamingo'; 'testbox' = '#testbox' }
    foreach ($k in $cases.Keys) {
        $got = Get-WatchSeatChannels -MachineId $k
        if ($got -ne $cases[$k]) { throw "'$k' -> '$got' (want $($cases[$k]))" }
        if ($got -match ',' -or $got -match '(?i)bobiverse|agentic_irc') { throw "worker channel list must be one channel: $got" }
    }
    $blank = Get-WatchSeatChannels -MachineId ''
    if ($blank -ne ('#' + ([string]$env:COMPUTERNAME).Trim().ToLowerInvariant())) { throw "blank machine id must fall back to #computername: $blank" }
}

Check 'AM10b Ensure-WatchIrcSeat passes only Get-WatchSeatChannels to irc_agent' {
    $body = (Get-Fn 'Ensure-WatchIrcSeat').Extent.Text
    if ($body -notmatch '\$channels = Get-WatchSeatChannels -MachineId \$mid') { throw 'must build --channel via Get-WatchSeatChannels' }
    if ($body -match '#bobiverse,' -or $body -match '#agentic_irc''') { throw 'must not pass #bobiverse / #agentic_irc' }
    if ($body -notmatch "'--channel', \`$channels") { throw 'irc_agent must get --channel $channels' }
}

Check 'AM10c seat prompt does not claim #bobiverse / #agentic_irc' {
    $src = Get-Content -LiteralPath $path -Raw
    if ($src -match 'Seat JOINs #bobiverse') { throw 'seat prompt must not tell the seat it is in #bobiverse' }
    if ($src -notmatch 'Seat JOINs its own #\{machine\} ONLY') { throw 'seat prompt must say own #{machine} only' }
}

if ($fail -gt 0) { Write-Host "Test-WorkerSeatChannel: $fail failed"; exit 1 }
Write-Host 'Test-WorkerSeatChannel: all passed'
exit 0
