# AgentMonitor self-tests (Windows PowerShell 5.1).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-AgentMonitor.ps1
[CmdletBinding()]
param([string]$OnlyCase)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:Pass = 0
$script:Fail = 0

function Invoke-Case {
    param([string]$Id, [scriptblock]$Body)
    if ($OnlyCase -and $Id -ne $OnlyCase) { return }
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

function Get-CloneStatus {
    $s = @(& git -C $RepoRoot status --porcelain --untracked-files=all)
    return ($s -join "`n")
}

Invoke-Case 'AM1 generated shortcuts lnk not tracked' {
    # Publish-DesktopShortcuts writes machine paths + exe icons into shortcuts\*.lnk on every
    # install; tracked copies left the Desktop clone dirty (9 x M shortcuts/*.lnk).
    $tracked = @(& git -C $RepoRoot ls-files -- 'shortcuts/*.lnk')
    if ($tracked.Count -gt 0) { throw "generated .lnk must not be tracked: $($tracked -join ', ')" }
    & git -C $RepoRoot check-ignore -q -- 'shortcuts/Watch-Agent Grok New.lnk'
    if ($LASTEXITCODE -ne 0) { throw '.gitignore must ignore shortcuts/*.lnk' }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'shortcuts\README.md'))) { throw 'shortcuts/README.md must explain the generated .lnk files' }
}

Invoke-Case 'AM2 publish shortcuts keeps clone clean' {
    $desk = Join-Path ([IO.Path]::GetTempPath()) ('am-desk-' + [guid]::NewGuid().ToString('N'))
    $before = Get-CloneStatus
    try {
        & (Join-Path $RepoRoot 'tools\Publish-DesktopShortcuts.ps1') -MonitorDir $RepoRoot -DesktopDir $desk | Out-Null
        $after = Get-CloneStatus
        if ($after -ne $before) { throw "Publish-DesktopShortcuts dirtied the clone:`n$after" }
        $deskLnk = @(Get-ChildItem -LiteralPath $desk -Filter '*.lnk')
        $repoLnk = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'shortcuts') -Filter '*.lnk')
        if ($deskLnk.Count -ne 9) { throw "expected 9 Desktop .lnk under -DesktopDir, got $($deskLnk.Count)" }
        if ($repoLnk.Count -lt 9) { throw "expected 9 repo shortcuts .lnk, got $($repoLnk.Count)" }
        $w = New-Object -ComObject WScript.Shell
        foreach ($l in $deskLnk) {
            $s = $w.CreateShortcut($l.FullName)
            if ($s.TargetPath -notmatch 'wscript\.exe$') { throw "$($l.Name): target must be wscript.exe" }
            if ($s.Arguments -notmatch 'Run-Hidden\.vbs' -or $s.Arguments -notmatch '-New' -or $s.Arguments -notmatch '-Windows off') { throw "$($l.Name): must launch Run-Hidden.vbs ... -New -Windows off" }
            if ($s.WorkingDirectory -ne $RepoRoot) { throw "$($l.Name): WorkingDirectory must be the clone ($($s.WorkingDirectory))" }
        }
    }
    finally {
        Remove-Item -LiteralPath $desk -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host "AM summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
