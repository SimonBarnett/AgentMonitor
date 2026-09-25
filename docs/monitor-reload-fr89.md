# Monitor reload (FR #89)

Safe hotpatch of `Watch-AgentHealth.ps1` without duplicating the agent TUI or renaming the seat:

1. Deploy the new script (Desktop clone or install path).
2. Stop **only** the monitor PowerShell process (not agent.exe / irc_agent).
3. Start the worker again with the same flags **plus `-Reload`**, e.g.

```text
powershell -NoProfile -ExecutionPolicy Bypass -File Watch-AgentHealth.ps1 -WatchWorker -Grok -Windows off -Reload
```

On start the monitor logs `build=FR89-adopt-live-tree` and, if `state.rootPid` is still alive and its command line contains `sessionId`, **adopts** that tree (no `Start-WatchedAgent` relaunch). Live `irc_agent` nick is kept via `Resolve-WatchSeatPid` (suffix from the agent command line).

Do not use `-New` for a hotpatch (that resets the session).
