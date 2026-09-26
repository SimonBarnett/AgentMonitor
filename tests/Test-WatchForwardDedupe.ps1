# FR #105: forward dedupe expires (~60s) and logs skips.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchForwardDedupe.ps1
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

foreach ($n in @('Test-WatchForwardDedupeHit', 'Set-WatchLastForward')) {
    . ([scriptblock]::Create((Get-Fn $n).Extent.Text))
}
$script:ForwardDedupeSeconds = 60

Check 'AM105a same line within TTL is a hit' {
    $t0 = [datetime]'2026-09-26T12:00:00'
    $st = [pscustomobject]@{}
    $st = Set-WatchLastForward -State $st -Line 'FROM Jeeves #marchhare :offer' -Now $t0
    if (-not (Test-WatchForwardDedupeHit -State $st -Line 'FROM Jeeves #marchhare :offer' -Now $t0.AddSeconds(30) -TtlSeconds 60)) {
        throw '30s age must still dedupe'
    }
}

Check 'AM105b same line after TTL is not a hit' {
    $t0 = [datetime]'2026-09-26T12:00:00'
    $st = [pscustomobject]@{}
    $st = Set-WatchLastForward -State $st -Line 'FROM Jeeves #marchhare :offer' -Now $t0
    if (Test-WatchForwardDedupeHit -State $st -Line 'FROM Jeeves #marchhare :offer' -Now $t0.AddSeconds(60) -TtlSeconds 60) {
        throw 'at TTL boundary must allow re-forward'
    }
    if (Test-WatchForwardDedupeHit -State $st -Line 'FROM Jeeves #marchhare :offer' -Now $t0.AddSeconds(61) -TtlSeconds 60) {
        throw 'after TTL must allow re-forward'
    }
}

Check 'AM105c different line never hits' {
    $t0 = [datetime]'2026-09-26T12:00:00'
    $st = Set-WatchLastForward -State ([pscustomobject]@{}) -Line 'FROM A' -Now $t0
    if (Test-WatchForwardDedupeHit -State $st -Line 'FROM B' -Now $t0.AddSeconds(1) -TtlSeconds 60) {
        throw 'different line must not dedupe'
    }
}

Check 'AM105d legacy state without lastForwardUtc does not forever-drop' {
    $st = [pscustomobject]@{ lastForwardLine = 'FROM Jeeves #marchhare :offer' }
    if (Test-WatchForwardDedupeHit -State $st -Line 'FROM Jeeves #marchhare :offer' -Now (Get-Date) -TtlSeconds 60) {
        throw 'missing timestamp must not forever-drop (treat as expired)'
    }
}

Check 'AM105e source wires TTL + skip log' {
    $src = Get-Content -LiteralPath $path -Raw
    if ($src -notmatch '\[int\]\$ForwardDedupeSeconds = 60') { throw 'default ForwardDedupeSeconds must be 60' }
    if ($src -notmatch 'forward skipped \(duplicate within') { throw 'must log skipped duplicates' }
    if ($src -notmatch 'Test-WatchForwardDedupeHit') { throw 'Send-IrcLineToSession must use Test-WatchForwardDedupeHit' }
    if ($src -match 'lastForwardLine -eq \$Line\) \{\s*return \$State\s*\}') {
        throw 'must not forever-return on lastForwardLine equality alone'
    }
}

if ($fail -gt 0) { Write-Host "Test-WatchForwardDedupe: $fail failed"; exit 1 }
Write-Host 'Test-WatchForwardDedupe: all passed'
exit 0
