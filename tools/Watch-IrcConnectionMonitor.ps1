# Persistent IRC connection detector for watch-grok. Emits FAIL/DONE on state change.
param([int]$IntervalSeconds = 45)
$ErrorActionPreference = 'Continue'
$waw = Join-Path $PSScriptRoot 'Watch-AgentWatcher.ps1'
$prev = ''
while ($true) {
    Start-Sleep -Seconds ([Math]::Max(15, $IntervalSeconds))
    $ag = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            $cl -match 'irc_agent\.py' -and $cl -match 'agentic-irc-watch-grok'
        })
    $mon = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            $cl -match 'Watch-AgentHealth\.ps1' -and $cl -match '-WatchWorker'
        })
    $st = if ($ag.Count -gt 0 -and $mon.Count -gt 0) { 'OK' } else { 'FAIL' }
    if ($st -eq $prev) { continue }
    if ($st -eq 'FAIL') {
        Write-Output ("FAILED irc={0} mon={1}" -f $ag.Count, $mon.Count)
        if (Test-Path -LiteralPath $waw) {
            try {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $waw -Once -Heal | Out-Null
            }
            catch { }
        }
    }
    else {
        Write-Output ("DONE recovered irc={0} mon={1}" -f $ag.Count, $mon.Count)
    }
    $prev = $st
}
