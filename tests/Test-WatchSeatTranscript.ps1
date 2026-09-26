# FR #90: seat-wake-transcript + wake start/end logging for hidden -p forwards.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchSeatTranscript.ps1
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

foreach ($n in @('Get-WatchSeatTranscriptPath', 'Write-WatchSeatTranscript', 'Write-WatchLog')) {
    . ([scriptblock]::Create((Get-Fn $n).Extent.Text))
}

Check 'AM90a Write-WatchSeatTranscript visible to seat window path' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('am90-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $script:StateDir = $tmp
    $script:LogFile = Join-Path $tmp 'monitor.log'
    New-Item -ItemType File -Force -Path $script:LogFile | Out-Null
    function Write-Host { param($Object) }
    try {
        $tp = Get-WatchSeatTranscriptPath
        if ($tp -notmatch 'seat-wake-transcript\.log$') { throw "path=$tp" }
        Write-WatchSeatTranscript 'wake start kind=grok session=sid-test pid=4242 text=FROM Jeeves #marchhare :ping'
        if (-not (Test-Path -LiteralPath $tp)) { throw 'transcript missing' }
        $raw = Get-Content -LiteralPath $tp -Raw -Encoding UTF8
        if ($raw -notmatch 'wake start kind=grok session=sid-test pid=4242') { throw "transcript=$raw" }
        if ($raw -notmatch 'FROM Jeeves') { throw 'wake text missing from transcript' }
        $mon = Get-Content -LiteralPath $script:LogFile -Raw -Encoding UTF8
        if ($mon -notmatch 'wake start kind=grok') { throw 'monitor log missing wake start' }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Check 'AM90b source wires PassThru + exit watcher + pane' {
    $src = Get-Content -LiteralPath $path -Raw
    if ($src -notmatch 'Write-WatchSeatTranscript') { throw 'must write seat transcript' }
    if ($src -notmatch 'Ensure-WatchSeatTranscriptPane') { throw 'must ensure transcript pane' }
    if ($src -notmatch 'Start-WatchForwardExitWatcher') { throw 'must watch forward exit' }
    if ($src -notmatch 'wake start kind=grok') { throw 'grok forward must log wake start' }
    if ($src -notmatch 'wake start kind=cursor') { throw 'cursor forward must log wake start' }
    if ($src -notmatch 'wake end kind=') { throw 'exit watcher must log wake end' }
    if ($src -notmatch '-PassThru') { throw 'Start-Process forward must use -PassThru for PID' }
    if ($src -match '(?i)SendKeys|System\.Windows\.Forms\.SendKeys') { throw 'must not inject keystrokes' }
}

Check 'AM90c docs name transcript pane' {
    $readme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw
    if ($readme -notmatch 'seat-wake-transcript') { throw 'README must name seat-wake-transcript.log' }
    if ($readme -notmatch 'FR #90') { throw 'README must mention FR #90' }
    $skill = Get-Content -LiteralPath (Join-Path $RepoRoot '.grok\skills\watch-seat\SKILL.md') -Raw
    if ($skill -notmatch 'wake transcript') { throw 'watch-seat skill must document transcript' }
}

if ($fail -gt 0) { Write-Host "Test-WatchSeatTranscript: $fail failed"; exit 1 }
Write-Host 'Test-WatchSeatTranscript: all passed'
exit 0
