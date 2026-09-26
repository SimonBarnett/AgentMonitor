# FR #91: wake timeout, serialize queue, orphan -p reap (never touch TUI without -p).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchWakeLifecycle.ps1
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
        'Test-WatchProcessAlive',
        'Test-WatchWakeInFlight',
        'Clear-WatchWakeState',
        'Add-WatchWakeQueue',
        'Pop-WatchWakeQueue',
        'Stop-OrphanWatchWakeProcesses',
        'Sync-WatchWakeLifecycle',
        'Write-WatchLog',
        'Write-WatchSeatTranscript',
        'Get-WatchSeatTranscriptPath',
        'Test-WatchAgentWakeBusy',
        'Test-CursorAgentForwardBusy'
    )) {
    . ([scriptblock]::Create((Get-Fn $n).Extent.Text))
}

# Stubs for nested calls Sync may make
function Send-IrcLineToSession {
    param($State, [string]$Line)
    $script:DequeuedLines += ,[string]$Line
    return $State
}
function Test-WatchAgentWakeBusy { param([string]$SessionId, [switch]$GrokKind) return $false }
function Test-CursorAgentForwardBusy { param([string]$SessionId) return $false }

$script:WakeTimeoutSeconds = 2
$script:WakeQueueMax = 5
$script:KindName = 'grok'
$script:DequeuedLines = @()

Check 'AM91a fake never-exit wake killed after timeout' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('am91a-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $script:StateDir = $tmp
    $script:LogFile = Join-Path $tmp 'mon.log'
    New-Item -ItemType File -Force -Path $script:LogFile | Out-Null
    function Write-Host { param($Object) }
    $hang = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList @(
        '-NoProfile', '-Command', 'Start-Sleep -Seconds 120'
    ) -WindowStyle Hidden -PassThru
    try {
        $st = [pscustomobject]@{
            sessionId      = 'sid-timeout'
            wakePid        = [int]$hang.Id
            wakeStartedUtc = (Get-Date).AddSeconds(-5)
            wakeKind       = 'grok'
            wakeQueue      = @()
        }
        $st = Sync-WatchWakeLifecycle -State $st -Now (Get-Date) -StartNext:$false
        if ([int]$st.wakePid -ne 0) { throw "wakePid should clear after timeout, got $($st.wakePid)" }
        Start-Sleep -Milliseconds 400
        if (Get-Process -Id $hang.Id -ErrorAction SilentlyContinue) {
            throw 'hung process should be killed'
        }
        $log = Get-Content -LiteralPath $script:LogFile -Raw -Encoding UTF8
        if ($log -notmatch 'wake timeout') { throw "log missing wake timeout: $log" }
    }
    finally {
        Stop-Process -Id $hang.Id -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Check 'AM91b two FROM while busy queue then one after' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('am91b-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $script:StateDir = $tmp
    $script:LogFile = Join-Path $tmp 'mon.log'
    New-Item -ItemType File -Force -Path $script:LogFile | Out-Null
    function Write-Host { param($Object) }
    $script:DequeuedLines = @()
    $hold = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList @(
        '-NoProfile', '-Command', 'Start-Sleep -Seconds 30'
    ) -WindowStyle Hidden -PassThru
    try {
        $st = [pscustomobject]@{
            sessionId      = 'sid-q'
            wakePid        = [int]$hold.Id
            wakeStartedUtc = Get-Date
            wakeKind       = 'grok'
            wakeQueue      = @()
        }
        $st = Add-WatchWakeQueue -State $st -Line 'FROM A #m :one'
        $st = Add-WatchWakeQueue -State $st -Line 'FROM A #m :two'
        $st = Add-WatchWakeQueue -State $st -Line 'FROM A #m :one' # coalesce
        if (@($st.wakeQueue).Count -ne 2) { throw "queue depth=$(@($st.wakeQueue).Count) want 2" }
        # Still in flight — Sync must not dequeue
        $st = Sync-WatchWakeLifecycle -State $st -StartNext
        if ($script:DequeuedLines.Count -ne 0) { throw 'must not dequeue while wake alive' }
        Stop-Process -Id $hold.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
        $st = Sync-WatchWakeLifecycle -State $st -StartNext
        if ($script:DequeuedLines.Count -lt 1) { throw 'expected dequeue after wake exit' }
        if ($script:DequeuedLines[0] -ne 'FROM A #m :one') { throw "first dequeued=$($script:DequeuedLines[0])" }
    }
    finally {
        Stop-Process -Id $hold.Id -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Check 'AM91c orphan -p reaped; TUI without -p untouched' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('am91c-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $script:StateDir = $tmp
    $script:LogFile = Join-Path $tmp 'mon.log'
    New-Item -ItemType File -Force -Path $script:LogFile | Out-Null
    function Write-Host { param($Object) }
    # Simulate orphan: powershell whose command line looks like forward-cursor.ps1 under StateDir, parent dead.
    # We can't easily forge ParentProcessId; instead assert Stop-OrphanWatchWakeProcesses skips agent without -p
    # by source contract + that interactive sleep without -p survives a reap pass for grok filter.
    $tui = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList @(
        '-NoProfile', '-Command', 'Start-Sleep -Seconds 60'
    ) -WindowStyle Hidden -PassThru
    try {
        $n = Stop-OrphanWatchWakeProcesses -SessionId 'sid-none' -GrokKind
        # Our sleep is powershell.exe not agent.exe — must not be killed by grok orphan pass
        if (-not (Get-Process -Id $tui.Id -ErrorAction SilentlyContinue)) {
            throw 'non-agent process must not be reaped by grok orphan pass'
        }
        $src = Get-Content -LiteralPath $path -Raw
        if ($src -notmatch "if \(\`$cl -notmatch ' -p\(\\s\|\$\)'\) \{ continue \}") {
            # allow equivalent pattern
            if ($src -notmatch " -p\(\\s\|\$\)'\) \{ continue \}") {
                throw 'orphan reap must skip processes without -p (live TUI)'
            }
        }
        if ($src -notmatch 'wake timeout') { throw 'must log wake timeout' }
        if ($src -notmatch 'Add-WatchWakeQueue') { throw 'must queue while busy' }
        if ($src -notmatch 'Stop-OrphanWatchWakeProcesses') { throw 'must reap orphans on start' }
        if ($src -notmatch '\[int\]\$WakeTimeoutSeconds = 1800') { throw 'default WakeTimeoutSeconds 1800' }
    }
    finally {
        Stop-Process -Id $tui.Id -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($fail -gt 0) { Write-Host "Test-WatchWakeLifecycle: $fail failed"; exit 1 }
Write-Host 'Test-WatchWakeLifecycle: all passed'
exit 0
