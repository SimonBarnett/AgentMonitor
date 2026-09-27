# FR #131: Report-WatchException files via gh (fake), dedupes, never throws.
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:Pass = 0
$script:Fail = 0

function Check {
    param([string]$Id, [scriptblock]$Body)
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

function Import-WatchFunctions {
    param([string[]]$Names)
    $path = Join-Path $RepoRoot 'Watch-AgentHealth.ps1'
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    foreach ($n in $Names) {
        $fn = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $n }, $true)
        if (-not $fn) { throw "missing function $n" }
        . ([scriptblock]::Create($fn.Extent.Text))
        Set-Item -Path ("function:script:" + $n) -Value (Get-Item ("function:" + $n)).ScriptBlock
    }
}

Check 'AM131a source: Report-WatchException + forward/loop wiring' {
    $src = Get-Content -LiteralPath (Join-Path $RepoRoot 'Watch-AgentHealth.ps1') -Raw -Encoding UTF8
    if ($src -notmatch 'function Report-WatchException') { throw 'Report-WatchException missing' }
    if ($src -notmatch "'issue',\s*'create'") { throw 'must use gh issue create' }
    if ($src -match 'Invoke-RestMethod.*openai') { throw 'must not call LLM for issue text' }
    if ($src -notmatch "Site 'Send-IrcLineToSession'") { throw 'forward catch must report' }
    if ($src -notmatch "Site 'WatchLoop'") { throw 'watch loop must report' }
    if ($src -notmatch "Site 'WatchFatal'") { throw 'watch fatal must report' }
}

Check 'AM131b fake gh creates one issue payload; dedupe skips flood' {
    Import-WatchFunctions -Names @('Get-WatchExceptionFingerprint', 'Report-WatchException', 'Write-WatchLog')
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('am131-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $fakeGh = Join-Path $tmp 'gh.cmd'
    $log = Join-Path $tmp 'gh-invocations.log'
    @"
@echo off
echo %*>> "$log"
echo https://github.com/SimonBarnett/AgentMonitor/issues/999
exit /b 0
"@ | Set-Content -LiteralPath $fakeGh -Encoding ASCII
    $script:StateDir = $tmp
    $script:LogFile = Join-Path $tmp 'watch.log'
    $script:StatePath = Join-Path $tmp 'state.json'
    '{"sessionId":"sess-am131","ircHome":"C:\\tmp\\irc"}' | Set-Content -LiteralPath $script:StatePath -Encoding utf8
    try {
        try { 1 / 0 } catch { $err = $_ }
        $r1 = Report-WatchException -ErrorRecord $err -Site 'Send-IrcLineToSession' -GhExe $fakeGh -DedupeHours 12
        if (-not $r1.ok) { throw 'first report must ok' }
        if ($r1.deduped) { throw 'first report must not dedupe' }
        if (-not (Test-Path -LiteralPath $log)) { throw 'fake gh not invoked' }
        $lines1 = @(Get-Content -LiteralPath $log)
        if ($lines1.Count -lt 1) { throw 'expected gh invocation' }
        if ($lines1[0] -notmatch 'issue create') { throw "expected issue create: $($lines1[0])" }
        if ($lines1[0] -notmatch 'SimonBarnett/AgentMonitor') { throw 'wrong repo' }
        $bodyFiles = @(Get-ChildItem -LiteralPath $tmp -Filter 'exception-issue-*.md')
        if ($bodyFiles.Count -lt 1) { throw 'body-file missing' }
        $body = Get-Content -LiteralPath $bodyFiles[0].FullName -Raw
        if ($body -notmatch 'fingerprint') { throw 'body missing fingerprint' }
        if ($body -notmatch 'sess-am131') { throw 'body missing session' }
        if ($body -match '(?i)password=|xai_api_key|CURSOR_API_KEY=') { throw 'secrets in body' }

        $r2 = Report-WatchException -ErrorRecord $err -Site 'Send-IrcLineToSession' -GhExe $fakeGh -DedupeHours 12
        if (-not $r2.deduped) { throw 'second report must dedupe' }
        $lines2 = @(Get-Content -LiteralPath $log)
        if ($lines2.Count -ne $lines1.Count) { throw 'dedupe must not invoke gh again' }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ("Summary PASS={0} FAIL={1}" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
