# FR #124: PowerShell 5.1 must not assign read-only $HOME / $home in Initialize-WatchIrcHome.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchPs51Home.ps1
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$path = Join-Path $RepoRoot 'Watch-AgentHealth.ps1'
$fail = 0

function Check([string]$Id, [scriptblock]$Body) {
    try { & $Body; Write-Host "PASS $Id" } catch { $script:fail++; Write-Host "FAIL $Id :: $($_.Exception.Message)" }
}

Check 'AM124b source never assigns to $home in Initialize-WatchIrcHome' {
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    $fn = $ast.Find({
            param($a)
            $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Initialize-WatchIrcHome'
        }, $true)
    if (-not $fn) { throw 'Initialize-WatchIrcHome missing' }
    $text = $fn.Extent.Text
    if ($text -match '(?m)^\s*\$home\s*=') {
        throw 'Initialize-WatchIrcHome must not assign $home (PS 5.1 $HOME is read-only)'
    }
    if ($text -notmatch '\$boundHome') {
        throw 'Initialize-WatchIrcHome should use $boundHome (or another non-HOME name)'
    }
}

Check 'AM124c Initialize-WatchIrcHome runs on this host PowerShell' {
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "expected Windows PowerShell 5+, got $($PSVersionTable.PSVersion)"
    }
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    $fn = $ast.Find({
            param($a)
            $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Initialize-WatchIrcHome'
        }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    function Get-WatchBoundIrcHome { return $script:__am124Home }
    function Test-ForbiddenIrcHome { param([string]$ResolvedHome) return $false }
    $script:IrcHome = ''
    $script:ClientSlot = 1
    $seat = Join-Path ([IO.Path]::GetTempPath()) ('am124-home-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $seat | Out-Null
    try {
        # Prove raw $home assign still fails on this runtime (documents the bug class).
        try {
            Set-Variable -Name home -Value 'should-fail' -ErrorAction Stop
            # Some hosts allow it; only require our function path to succeed.
        }
        catch {
            if ($_.Exception.Message -notmatch 'read-only|constant|Cannot overwrite') {
                throw "unexpected HOME assign error: $($_.Exception.Message)"
            }
        }
        $script:__am124Home = $seat
        $st = [pscustomobject]@{ ircHome = '' }
        $st2 = Initialize-WatchIrcHome -State $st
        $want = [IO.Path]::GetFullPath($seat)
        if ([string]$st2.ircHome -ne $want) {
            throw "ircHome=$($st2.ircHome) want $want"
        }
    }
    finally {
        Remove-Item -LiteralPath $seat -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($fail -gt 0) { Write-Host "Test-WatchPs51Home: $fail failed"; exit 1 }
Write-Host 'Test-WatchPs51Home: all passed'
exit 0
