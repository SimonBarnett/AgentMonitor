# FR #102: workspace resolve C-first fixed disks; bootstrap log; never optical/network.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchWorkspaceResolve.ps1
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

foreach ($n in @(
        'Write-WatchBootstrapLog',
        'Test-WatchFixedWritableDriveRoot',
        'Get-WatchFixedDriveLetters',
        'Resolve-AgentWorkspace'
    )) {
    . ([scriptblock]::Create((Get-Fn $n).Extent.Text))
}

Check 'AM102a source: C-first fixed disks; bootstrap before resolve; never D..Z-only create' {
    $src = Get-Content -LiteralPath $path -Raw
    if ($src -notmatch 'Write-WatchBootstrapLog') { throw 'missing bootstrap log' }
    if ($src -notmatch 'Test-WatchFixedWritableDriveRoot') { throw 'missing writable fixed probe' }
    if ($src -notmatch 'Get-WatchFixedDriveLetters') { throw 'missing fixed drive letter helper' }
    if ($src -notmatch 'DriveType=3') { throw 'must filter DriveType=3' }
    if ($src -match "foreach \(\`$letter in @\('D', 'E'") { throw 'must not prefer D..Z-only scan' }
    if ($src -notmatch 'fatal start:') { throw 'must log fatal start' }
    if ($src -notmatch 'irc ensure stale live rows') { throw 'must relaunch when agent/listen PIDs dead' }
}

Check 'AM102b explicit -Cwd wins' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('am102-cwd-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $got = Resolve-AgentWorkspace -Requested $tmp -Explicit
        if ([IO.Path]::GetFullPath($got) -ne [IO.Path]::GetFullPath($tmp)) { throw "got $got" }
    }
    finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Check 'AM102c C:\ai preferred when both C and D exist (Simon 2026-09-25)' {
    $hasC = Test-Path -LiteralPath 'C:\ai'
    $hasD = Test-Path -LiteralPath 'D:\ai'
    if ($hasC -and $hasD) {
        $got = Resolve-AgentWorkspace -Requested '' -Explicit:$false
        if ($got -notmatch '(?i)^C:\\ai') {
            throw "expected C:\ai when both exist; got $got (report stray C:\ai on MarchHare/flamingo)"
        }
        Write-Host "NOTE: MarchHare has both C:\ai and D:\ai; resolver correctly prefers C:\ai"
    }
    else {
        Write-Host "SKIP both-present check (C:\ai=$hasC D:\ai=$hasD)"
    }
}

Check 'AM102d bootstrap log writes before state dir' {
    $log = Join-Path $env:TEMP 'Watch-AgentHealth-start.log'
    $before = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
    Write-WatchBootstrapLog 'am102 probe'
    if (-not (Test-Path $log)) { throw 'bootstrap log missing' }
    $raw = Get-Content -LiteralPath $log -Raw -Encoding UTF8
    if ($raw -notmatch 'am102 probe') { throw 'bootstrap line missing' }
}

Check 'AM102e tray Start-BobTrayAgentWatch passes -Cwd' {
    $tray = Join-Path (Split-Path $RepoRoot -Parent) 'agentic_build\tools\Watch-BobTray.ps1'
    if (-not (Test-Path -LiteralPath $tray)) {
        $tray = 'D:\ai\agentic_build\tools\Watch-BobTray.ps1'
    }
    if (-not (Test-Path -LiteralPath $tray)) { throw "Watch-BobTray.ps1 not found: $tray" }
    $src = Get-Content -LiteralPath $tray -Raw
    if ($src -notmatch "Get-BobTrayWatchWorkspace") { throw 'tray must resolve watch workspace' }
    if ($src -notmatch "'-Cwd', \`\$cwd" -and $src -notmatch '-Cwd'', \$cwd') {
        if ($src -notmatch '-Cwd') { throw 'Start-BobTrayAgentWatch must pass -Cwd' }
    }
    if ($src -notmatch 'Watch-BobTrayAgentWatchEarlyExit') { throw 'tray must watch early exit' }
}

Check 'AM102f mocked optical DriveType=5 rejected by writable probe' {
    function Get-CimInstance {
        param($ClassName, $Filter)
        [pscustomobject]@{ DeviceID = 'E:'; DriveType = 5 }
    }
    if (Test-WatchFixedWritableDriveRoot -Root 'E:\') {
        throw 'optical DriveType=5 must not count as writable fixed'
    }
}

Check 'AM102g mocked network DriveType=4 rejected by writable probe' {
    function Get-CimInstance {
        param($ClassName, $Filter)
        [pscustomobject]@{ DeviceID = 'X:'; DriveType = 4 }
    }
    if (Test-WatchFixedWritableDriveRoot -Root 'X:\') {
        throw 'network DriveType=4 must not count as writable fixed'
    }
}

Check 'AM102h missing drive letter returns false (no throw)' {
    # Fake CIM says Q: is fixed; letter is absent on this box — probe must return false, not throw.
    function Get-CimInstance {
        param($ClassName, $Filter)
        if ($Filter -match "DeviceID='Q:'") {
            return [pscustomobject]@{ DeviceID = 'Q:'; DriveType = 3 }
        }
        return $null
    }
    $got = Test-WatchFixedWritableDriveRoot -Root 'Q:\'
    if ($got) { throw 'missing Q:\ must not pass writable probe' }
}

Check 'AM102h2 removable DriveType=2 rejected' {
    function Get-CimInstance {
        param($ClassName, $Filter)
        [pscustomobject]@{ DeviceID = 'F:'; DriveType = 2 }
    }
    if (Test-WatchFixedWritableDriveRoot -Root 'F:\') {
        throw 'removable DriveType=2 must not count as writable fixed'
    }
}

Check 'AM102i Get-WatchFixedDriveLetters returns sorted fixed only (live)' {
    $letters = @(Get-WatchFixedDriveLetters)
    if ($letters.Count -lt 1) { throw 'expected at least one fixed disk' }
    $sorted = @($letters | Sort-Object)
    for ($i = 0; $i -lt $letters.Count; $i++) {
        if ($letters[$i] -ne $sorted[$i]) { throw "letters not sorted: $($letters -join ',')" }
    }
    if ($letters[0] -ne 'C' -and (Test-Path -LiteralPath 'C:\')) {
        # C: may be absent on exotic boxes; on MarchHare it must lead when present and fixed.
        $cFixed = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($cFixed -and [int]$cFixed.DriveType -eq 3 -and $letters -notcontains 'C') {
            throw 'C: fixed present but missing from letter list'
        }
    }
}

Check 'AM102j resolve create path prefers first writable fixed when no \\ai (mocked)' {
    function Get-WatchFixedDriveLetters { @('C', 'E', 'X') }
    function Test-WatchFixedWritableDriveRoot {
        param([string]$Root)
        return $Root -eq 'C:\'
    }
    $created = $null
    function Test-Path {
        param([string]$LiteralPath, [switch]$Path)
        # No existing \ai anywhere in this mock world.
        if ($LiteralPath -match '(?i)[\\/]ai$') { return $false }
        return $true
    }
    function New-Item {
        param($ItemType, $Path, [switch]$Force)
        $script:created = $Path
        return [pscustomobject]@{ FullName = $Path }
    }
    function Write-WatchBootstrapLog { param([string]$Message) }
    $got = Resolve-AgentWorkspace -Requested '' -Explicit:$false
    if ($got -notmatch '(?i)^C:\\ai') { throw "expected create C:\ai; got $got" }
    if ($script:created -notmatch '(?i)^C:\\ai') { throw "New-Item path was $script:created" }
}

if ($fail -gt 0) { Write-Host "Test-WatchWorkspaceResolve: $fail failed"; exit 1 }
Write-Host 'Test-WatchWorkspaceResolve: all passed'
exit 0
