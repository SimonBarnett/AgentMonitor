# AgentMonitor #133: seed forbids PRIVMSG-wrap for ACK/DONE; prefers bare keyword lines.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$path = Join-Path $root 'Watch-AgentHealth.ps1'
$src = Get-Content -LiteralPath $path -Raw
if ($src -match 'Prefer: PRIVMSG #\{machine\} :<payload>') {
    throw 'seed must not prefer PRIVMSG-wrap for ACK/DONE'
}
if ($src -notmatch 'ACK/DONE are BARE lines only') {
    throw 'seed must require bare ACK/DONE'
}
if ($src -notmatch 'Do NOT wrap ACK/DONE as PRIVMSG') {
    throw 'seed must forbid PRIVMSG-wrap ACK/DONE'
}
$skill = Join-Path $root '.grok\skills\watch-seat\SKILL.md'
$sk = Get-Content -LiteralPath $skill -Raw
if ($sk -match '(?m)^PRIVMSG #marchhare :ACK ') {
    throw 'watch-seat skill must not exemplify PRIVMSG-wrapped ACK'
}
if ($sk -notmatch 'wrap ACK/DONE as') {
    throw 'watch-seat skill must forbid PRIVMSG-wrap ACK/DONE'
}
if ($sk -notmatch '(?i)bare') {
    throw 'watch-seat skill must mention bare outbox lines'
}
Write-Host 'PASS AM133 bare ACK/DONE outbox'
exit 0
