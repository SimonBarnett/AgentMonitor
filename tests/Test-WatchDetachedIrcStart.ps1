# Static checks: IRC ensure must start via Start-WatchDetachedProcess (job breakaway).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'Watch-AgentHealth.ps1'
$text = [IO.File]::ReadAllText($script)
if ($text -notmatch 'function Start-WatchDetachedProcess') { throw 'missing Start-WatchDetachedProcess' }
if ($text -notmatch 'watch-detached') { throw 'Start-WatchDetachedProcess must use cmd start /B breakaway title' }
if ($text -notmatch 'Start-WatchDetachedProcess -FilePath \$py -ArgumentString \$agentArgs') {
    throw 'Ensure-WatchIrcSeat agent start must call Start-WatchDetachedProcess'
}
if ($text -notmatch 'Start-WatchDetachedProcess -FilePath \$py -ArgumentString \$listenArgs') {
    throw 'Ensure-WatchIrcSeat listen start must call Start-WatchDetachedProcess'
}
$ensureChunk = if ($text -match '(?s)if \(\$agents\.Count -eq 0\) \{.*?\$didConnect = \$true') { $Matches[0] } else { '' }
if (-not $ensureChunk) { throw 'could not locate agents.Count -eq 0 ensure block' }
if ($ensureChunk -match 'Start-Process -FilePath \$py') {
    throw 'Ensure agent still uses Start-Process -FilePath $py (job-bound)'
}
Write-Host 'Test-WatchDetachedIrcStart PASS'
