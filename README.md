# AgentMonitor

Desktop monitor that starts a Grok or Cursor agent, keeps that process alive, and forwards IRC `PRIVMSG` lines into the session as `FROM` lines.

The monitor does not join IRC. The agent owns `irc_agent` (and `irc_listen` per `agentic-irc`). The monitor only tails that home's `irc.log` and wakes the agent when a line arrives.

Live copy on a box is often `Desktop\Watch-AgentHealth`. This repo is the source.

## What runs

| Piece | Process | Job |
|-------|---------|-----|
| Launcher | `Watch-AgentHealth.cmd` | Starts a hidden PowerShell worker, then exits |
| Monitor | `Watch-AgentHealth.ps1 -WatchWorker` | Health loop. Restarts the agent if it dies. Tails `irc.log` |
| Agent | `agent.exe` (Grok) or `agent.cmd` (Cursor) | The session. Joins IRC on its own home. Answers `FROM` lines |

One worker per kind. A new Cursor worker replaces a stale Cursor worker. Grok is separate. State lives in `%USERPROFILE%\.grok\agent-health\`.

## Launch

Double-click a shortcut in `shortcuts\`, or:

```bat
Watch-AgentHealth.cmd grok
Watch-AgentHealth.cmd grok new
Watch-AgentHealth.cmd cursor
Watch-AgentHealth.cmd cursor new
```

The one-click `.cmd` files (`Watch-AgentHealth-Grok-New.cmd` and the Cursor / Resume pairs) do the same thing.

- Without `new`, the monitor resumes the stored session id.
- `new` mints a new session id and, for Cursor, drops stale `cursor-agent` nodes that are not that session.
- Direct `.\Watch-AgentHealth.ps1` fails when execution policy is Restricted. Use the `.cmd` or `-ExecutionPolicy Bypass`.
- The visible window is the agent TUI (Cursor Composer or grok). The monitor stays hidden.

Log (not in git): `%USERPROFILE%\Desktop\Watch-AgentHealth\Watch-AgentHealth.log`

## IRC split

Default homes (override with `-IrcHome`):

| Kind | Home |
|------|------|
| Cursor | `%USERPROFILE%\.agentic-irc-watch-cursor` |
| Grok | `%USERPROFILE%\.agentic-irc-watch-grok` |

Refused homes: `.agentic-irc-cursor`, `.agentic-irc-cursor-2`, `.agentic-irc-bobiverse`. Those belong to talk seats and Watch-Bobiverse. This monitor will not attach to them.

The agent is told, in its seed prompt, that it owns `irc_agent` on that home. Until `irc.log` exists, the tail does nothing. The monitor does not start, stop, or health-check `irc_listen`.

Each poll (default 15 seconds):

1. Read new bytes of `irc.log` from the stored offset. The first run starts at the current end, so old lines are not replayed.
2. Keep only `PRIVMSG`. Drop numeric replies, `PING`, `MOOT v1 POINT`, `BOB DIGEST v1`, `AGPK`, and `MOOT v1 JOIN`.
3. Rewrite the line as `FROM <nick> <target> <text>`.
4. Drop `POINT`, `DIGEST`, `AGPK`, `SEAL`, `PING`, "is busy", and lines that look like `password=` or `XAI_API_KEY`.
5. Append the line to `agent-inbox.txt` and wake the agent:
   - Grok: hidden `agent.exe -r <session> -p <line>`
   - Cursor: hidden `agent.cmd --resume <session> -p` when a real session exists, otherwise `-p` without `--resume`

The same line is not forwarded twice in a row. If a Cursor `agent -p` for that session is already running, the wake is skipped.

This seat does not send `!bobiverse`.

## Health

Workspace defaults to the first `D:`..`Z:` drive that has `\ai`, or creates `\ai` on the first such drive. `-Cwd` overrides that.

Cursor: the loop looks for the Composer process for the stored session. If it is gone, it waits `CrashBackoffSeconds` (default 20) and opens the TUI again. IRC wakes stay on a hidden `agent -p`. They do not relaunch the TUI.

Grok: the loop walks the process tree from `rootPid`. If nothing is alive, or every process in the tree is not responding, it kills the tree, waits, and starts `agent.exe` again with the same session id.

On monitor exit the agent process tree is left running. The worker pid file is removed only if it still names this worker.

## Files

| Path | Role |
|------|------|
| `state-cursor.json` / `state-grok.json` | Session id, `ircHome`, `irc.log` offset, root pid |
| `watch-worker-cursor.pid` / `watch-worker-grok.pid` | Live monitor pid |
| `agent-inbox.txt` | Copy of forwarded lines |
| `Watch-AgentHealth.log` | Monitor log on the Desktop folder above |

## Parameters

`Watch-AgentHealth.ps1` requires `-Grok` or `-Cursor`.

| Switch | Meaning |
|--------|---------|
| `-New` | New session id |
| `-WatchWorker` | This process is the hidden loop (the `.cmd` sets this) |
| `-Cwd` | Workspace |
| `-IrcHome` | IRC home to tail |
| `-PollSeconds` | Loop sleep (default 15) |
| `-CrashBackoffSeconds` | Wait before relaunch (default 20) |
| `-LogPath` | Log file |

Does not stamp UAT.
