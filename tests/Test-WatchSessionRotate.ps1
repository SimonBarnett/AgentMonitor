# FR #99: oversized session archive + hung no-CPU rotate; max one pending -p.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchSessionRotate.ps1
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
        'Get-GrokSessionsRoot', 'Get-GrokCwdSessionBucket', 'Resolve-GrokSessionDir',
        'Get-WatchSessionSizeInfo', 'Test-WatchSessionNeedsRotation', 'Archive-WatchSessionDir',
        'Ensure-WatchSessionBeforeResume', 'New-WatchSessionId', 'Test-WatchForwardBusy',
        'Get-ProcessCpuSeconds', 'Update-WatchPendingForwardHang', 'Write-WatchLog',
        'Write-WatchSessionHealthReport', 'Test-WatchProcessAlive'
    )) {
    . ([scriptblock]::Create((Get-Fn $n).Extent.Text))
}

Check 'AM99 oversized session rotates archive never delete' {
    function Write-WatchLog { param([string]$Message) }
    function Write-WatchSessionHealthReport { param($Kind, $Event, $Fields) }
    $root = Join-Path ([IO.Path]::GetTempPath()) ('am99-' + [guid]::NewGuid().ToString('N'))
    $cwd = Join-Path $root 'work'
    New-Item -ItemType Directory -Force -Path $cwd | Out-Null
    $sessions = Join-Path $root 'sessions'
    $bucket = Join-Path $sessions (Get-GrokCwdSessionBucket -WorkDir $cwd)
    $sid = '972c6563-d6ac-4d95-9a7d-0ec509d158a6'
    $sess = Join-Path $bucket $sid
    New-Item -ItemType Directory -Force -Path $sess | Out-Null
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
    $env:BOB_GROK_SESSIONS_ROOT = $sessions
    $script:StateDir = Join-Path $root 'state'
    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    $st = [pscustomobject]@{ sessionId = $sid; seenSession = $true }
    $st2 = Ensure-WatchSessionBeforeResume -State $st -WorkDir $cwd -Kind 'grok'
    if ($st2.sessionId -eq $sid) { throw 'session id must change after oversized rotate' }
    if (Test-Path -LiteralPath $sess) { throw 'old session dir must be moved (archived)' }
    $archDirs = @(Get-ChildItem -LiteralPath $bucket -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '_archive-*' })
    if ($archDirs.Count -lt 1) { throw 'archive folder missing under session bucket' }
    $moved = Join-Path $archDirs[0].FullName $sid
    if (-not (Test-Path -LiteralPath $moved)) { throw "archived session missing at $moved" }
    if (-not (Test-Path -LiteralPath (Join-Path $moved 'updates.jsonl'))) { throw 'archive must keep updates.jsonl' }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\BOB_GROK_SESSIONS_ROOT -ErrorAction SilentlyContinue
}

Check 'AM99b hung no-cpu forward detects and rotates once' {
    function Write-WatchLog { param([string]$Message) }
    function Write-WatchSessionHealthReport { param($Kind, $Event, $Fields) }
    function Test-WatchProcessAlive { param([int]$ProcessId) return ($ProcessId -eq 4242) }
    function Get-ProcessCpuSeconds { param([int]$ProcessId) return 1.0 }
    function Send-IrcLineToSession {
        param($State, [string]$Line)
        $State | Add-Member -NotePropertyName 'redelivered' -NotePropertyValue $Line -Force
        return $State
    }
    function Resolve-GrokSessionDir { param($SessionId, $WorkDir, $SessionsRoot = '') return $null }
    $script:SessionHangMinutes = 0.001
    $Grok = $true
    $Cwd = $env:TEMP
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

Check 'AM99c max one pending forward busy' {
    function Write-WatchLog { param([string]$Message) }
    function Test-WatchProcessAlive { param([int]$ProcessId) return ($ProcessId -eq 99) }
    function Test-CursorAgentForwardBusy { param([string]$SessionId) return $false }
    $busy = Test-WatchForwardBusy -State ([pscustomobject]@{ pendingForwardPid = 99; sessionId = 'x' })
    if (-not $busy) { throw 'live pending pid must be busy' }
    $free = Test-WatchForwardBusy -State ([pscustomobject]@{ pendingForwardPid = 0; sessionId = 'x' })
    if ($free) { throw 'no pending should not be busy' }
}

Check 'AM99d source documents FR99 rotation' {
    $src = Get-Content -LiteralPath $path -Raw
    if ($src -notmatch 'Ensure-WatchSessionBeforeResume') { throw 'missing Ensure-WatchSessionBeforeResume' }
    if ($src -notmatch 'Archive-WatchSessionDir') { throw 'missing Archive-WatchSessionDir' }
    if ($src -notmatch 'Update-WatchPendingForwardHang') { throw 'missing hang detector' }
    if ($src -notmatch 'SessionMaxUpdatesMb') { throw 'missing SessionMaxUpdatesMb param' }
    if ($src -notmatch 'Move-Item') { throw 'archive must Move-Item not delete' }
}

if ($fail -gt 0) { Write-Host "Test-WatchSessionRotate: $fail failed"; exit 1 }
Write-Host 'Test-WatchSessionRotate: all passed'
exit 0
