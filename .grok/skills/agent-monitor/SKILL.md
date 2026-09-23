---
name: agent-monitor
description: >
  AgentMonitor / Watch-AgentHealth desktop watch seat. Starts Grok or Cursor,
  tails irc.log, forwards FROM into the session. Use when launching the
  watcher, Cursor New/Resume, no TUI, prune leftover cursor-agent nodes,
  print-only, -Windows off, or explaining what the monitor does.
---

# AgentMonitor

Deterministic **watch-seat** monitor (`Watch-AgentHealth.ps1`). It is not the IRC client and not a talk seat.

## Split

| Who | Owns |
|-----|------|
| Monitor | Start TUI, persist session, health, tail `irc.log`, forward each PRIVMSG as `FROM` |
| Agent | `irc_agent` / `irc_listen` (skill `agentic-irc`), act on forwarded `FROM`, outbox |

The agent does not run, restart, or reimplement the monitor. The monitor does not start/stop `irc_listen`. Each client starts **its own** `irc_listen` on **its** slot home. Sharing one listener would duplicate every PRIVMSG into every connected agent.

Fleet: this is the **only** way to create a persistent build-worker seat (`watch-agent-health` / `Start-BobWatchWorker.ps1` in `agentic_build`). Not Start-TalkSeat.

## Launch

Visible by default (watch console + agent TUI). There is **no `on` flag**.

```bat
Watch-AgentHealth.cmd cursor
Watch-AgentHealth.cmd cursor new
Watch-AgentHealth.cmd grok
Watch-AgentHealth.cmd grok off
```

- **`new`** — next free slot + fresh session id. Does not restart a live client.
- **`off`** — hide both windows; log still writes. One-shot `agent -p` forwards stay hidden.
- One-click `Watch-AgentHealth-*-*.cmd` and Desktop shortcuts start **hidden** (`-Windows off`, no watch console, no TUI). Log still writes.

Restricted ExecutionPolicy: use the `.cmd` wrappers (`-ExecutionPolicy Bypass`).

## Cursor TUI

Launch via `cursor-agent.ps1` and a **prompt file** (`launch-cursor-tui.ps1`, `-NoExit`). Never put the seed on `agent.cmd` / `cmd.exe` argv (spaces truncate; log used to blame OOM with 19 GB free).

`create-chat` may fail (local session id only). `--resume` waits until a run succeeds.

If Composer never appears: print-only, no TUI relaunch storm, `create-chat` once per `--new`. Hidden `agent -p` forwards stay available.

When the TUI exits for **any** reason: write `agent.quit.request` + `quit.req` on **that slot's** watch home. `irc_agent` PARTs then QUITs. Do **not** restart that worker, TUI, or irc_agent (multiple clients share the box; restart ghosts the others). Start a **new** client the same way as talk seats: another `Watch-AgentHealth.cmd cursor new` takes the next free slot (`.agentic-irc-watch-cursor-2`, `-3`, …). Never PART talk-seat / bobiverse homes.

## `--new` prune

Only the **previous watch session** plus hung `forward-cursor.ps1` / orphan `worker-server`. Never Stop-Process fleet `Git task` / `long-running-background-tasks` or another TUI.

A live `forward-cursor.ps1` counts as busy even without `--resume` on the node command line.

## IRC homes (watch only)

- `%USERPROFILE%\.agentic-irc-watch-cursor` (slot 1), `watch-cursor-2` … `-8`
- `%USERPROFILE%\.agentic-irc-watch-grok` (slot 1), `watch-grok-2` … `-8`

Forbidden: `.agentic-irc-cursor`, `cursor-2`, `.agentic-irc-bobiverse`. No `!bobiverse`. No UAT stamp.

Log: `%USERPROFILE%\Desktop\Watch-AgentHealth\Watch-AgentHealth.log` (slot 2+ uses `Watch-AgentHealth-N.log`). State: `~\.grok\agent-health\state-{cursor|grok}[-N].json`.

Watch-seat agent behaviour: skill `watch-seat`.
