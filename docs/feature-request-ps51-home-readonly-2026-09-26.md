# FR #124: Watch-AgentHealth PS 5.1 `$home` crash + stale DONE `!bored`

## Problem

Main `d05ea24` crashes on PowerShell 5.1 start:

`Cannot overwrite variable HOME because it is read-only`

`Initialize-WatchIrcHome` assigned `$home = …` (introduced by `532b06c`).

Also: after `-New`, monitor emitted `reason=start` then `reason=done` within ~4s because a pre-restart DONE remained in `outbox.txt` while `boredLastDoneKey` was empty.

## Fix

- Rename to `$boundHome` (never assign PowerShell's `$HOME` / `$home`).
- On `Sync-WatchBored` `reason=start`, seed `boredLastDoneKey` from the current outbox DONE.
- `-New` / `Reset-WatchSessionForNew` clears bored start/done markers so start re-arms cleanly.
- Restore ACK/DONE angle-bracket format strings in the fleet prompt (AM104a).
- AM7 uses a live `$PID` for session-match (dead fixture pid 32208).

## Tests

- `tests/Test-WatchPs51Home.ps1` (AM124b/c)
- `tests/Test-WatchBored.ps1` AM124a
- `tests/Test-WatchAckDoneWire.ps1` AM104a
- `tests/Test-AgentMonitor.ps1` AM7
