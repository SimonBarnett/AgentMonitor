# AgentMonitor operator playbook

**Feature request:** [Issue #1](https://github.com/SimonBarnett/AgentMonitor/issues/1). **MRB:** [Issue #3](https://github.com/SimonBarnett/AgentMonitor/issues/3) (Bob chairs). This document does **not** stamp ready for human UAT.

AgentMonitor is `Watch-AgentHealth.ps1` plus `.cmd` launchers in this repo. It starts a **watch-seat** Grok or Cursor agent, keeps the agent process healthy, and forwards IRC traffic into that session. The agent still owns IRC per `agentic-irc`; the monitor does not replace it.

---

## What it does

| Responsibility | Owner |
|----------------|--------|
| Start `agent.exe` (Grok) or `agent.cmd` (Cursor) TUI | Monitor |
| Persist session id; resume without reloading all skills | Monitor (`~\.grok\agent-health\state-{grok\|cursor}.json`) |
| Connect to IRC (`irc_agent`, `irc_listen` per skill) | Agent |
| Tail IRC debug log and inject `FROM` lines into the session | Monitor |
| Health-check / restart crashed agent tree | Monitor |
| Start, stop, or health-check `irc_listen` | **Not** the monitor |

The hidden **watch worker** (`-WatchWorker`) runs the loop. The entry `.cmd` files spawn it with `-ExecutionPolicy Bypass` and open the visible Composer / Grok TUI (no extra PowerShell TUI launcher).

---

## Grok vs Cursor

| Switch | Binary | IRC home default |
|--------|--------|------------------|
| `grok` | `agent.exe` | `%USERPROFILE%\.agentic-irc-watch-grok` |
| `cursor` | `agent.cmd` | `%USERPROFILE%\.agentic-irc-watch-cursor` |

Pass exactly one of `-Grok` / `-Cursor` (or `grok` / `cursor` on the main `.cmd`).

---

## Resume vs `new`

- **Resume** (default): reuses the stored `sessionId` so the agent resumes the same session and does not reload all skills from scratch.
- **`new`**: generates a fresh `sessionId`, clears tail offsets, and starts a clean watch session. For Cursor, stale `cursor-agent` nodes for other sessions may be pruned.

Examples (from repo root):

```bat
Watch-AgentHealth.cmd grok
Watch-AgentHealth.cmd grok new
Watch-AgentHealth.cmd cursor
Watch-AgentHealth.cmd cursor new
```

One-click equivalents:

| File | Effect |
|------|--------|
| `Watch-AgentHealth-Grok-Resume.cmd` | Grok, resume |
| `Watch-AgentHealth-Grok-New.cmd` | Grok, `new` |
| `Watch-AgentHealth-Cursor-Resume.cmd` | Cursor, resume |
| `Watch-AgentHealth-Cursor-New.cmd` | Cursor, `new` |

---

## IRC: own watch home only

**LOCKED** — use only the watch IRC homes:

- `%USERPROFILE%\.agentic-irc-watch-grok`
- `%USERPROFILE%\.agentic-irc-watch-cursor`

**Forbidden** (monitor refuses `-IrcHome` pointing here):

- `%USERPROFILE%\.agentic-irc-cursor`
- `%USERPROFILE%\.agentic-irc-cursor-2`
- `%USERPROFILE%\.agentic-irc-bobiverse` (bobiverse Watch / talk-seat home)

Do not point the watch seat at another agent’s IRC home.

### `irc.log` and `FROM` forwarding

1. The agent writes IRC debug lines to **`$IrcHome\irc.log`** (agent firehose).
2. The monitor tails `irc.log` (does not duplicate `irc_listen` or TSR as a second listener).
3. Each new **PRIVMSG** line is parsed; eligible messages become a single line:

   `FROM <nick> <target> <text>`

   and are resume-forwarded into the agent session.

4. On first tail after start/resume without a saved offset, the monitor begins at **end of file** (no backlog flood).

Filtered out (not forwarded): server numeric replies, raw `PING …` lines (in `Convert-IrcRawLineToFromLine`), certain MOOT/AGPK/ACTION patterns there, and in `Test-DropIrcLine` spaced tokens ` POINT `, ` DIGEST `, ` AGPK `, ` SEAL `, and case-sensitive ` PING ` (lowercase chat such as `ping me` forwards).

**LOCKED:** This seat does **not** send `!bobiverse`. Agents follow `agentic-irc` for Ergo join/talk from this home.

---

## Workspace (`-Cwd`)

Default working directory is **`\ai` on the first available drive D: through Z:** (use existing folder or create `\ai`). The monitor does **not** default to `C:\` unless the operator passes **`-Cwd`** explicitly.

---

## Launch on Restricted ExecutionPolicy

**LOCKED:** Running `.\Watch-AgentHealth.ps1` directly often fails when policy is **Restricted**.

Use:

- Any `Watch-AgentHealth*.cmd` in this repo (they call `powershell.exe -NoProfile -ExecutionPolicy Bypass`), or
- An equivalent manual invoke with `-ExecutionPolicy Bypass`.

The main wrapper also uses `-WindowStyle Hidden` for the worker and passes `-WatchWorker`.

---

## Logs and state (not in git)

| Item | Default location |
|------|------------------|
| Monitor log | `%USERPROFILE%\Desktop\Watch-AgentHealth\Watch-AgentHealth.log` |
| Session state | `%USERPROFILE%\.grok\agent-health\state-grok.json` or `state-cursor.json` |
| Worker pid file | `%USERPROFILE%\.grok\agent-health\watch-worker-{grok\|cursor}.pid` |

Override monitor log with `-LogPath` when invoking the script directly (advanced).

Do not commit logs, state files, IRC homes, or secrets.

---

## What this repo does **not** do

- Stamp **ready for human UAT** (workers do not stamp UAT).
- Send **`!bobiverse`** from the watch seat.
- Manage bobiverse **Watch** (`Watch-BobAgents` / bobiverse IRC home).
- Document or ship Desktop shortcut **icon paths** (see UNKNOWN below).

---

## LOCKED vs UNKNOWN

### LOCKED (script header + FR 2026-09-23)

1. `--grok` / `--cursor` switch (`agent.exe` vs `agent.cmd`).
2. Persist session id; `new` = fresh session.
3. Monitor does not start/stop/health-check `irc_listen`.
4. Tail `$IrcHome/irc.log`; forward PRIVMSG as `FROM` into the agent session.
5. Own IRC home only (`.agentic-irc-watch-*`); forbidden homes listed above.
6. Launch via `.cmd` / `-ExecutionPolicy Bypass` on Restricted policy boxes.
7. Workspace `\ai` on D:..Z: unless `-Cwd` passed.
8. No UAT stamp; no `!bobiverse`.
9. Hidden `-WatchWorker`; opens Cursor Composer / Grok TUI directly.

### UNKNOWN

- Exact Desktop shortcut icon paths on each fleet machine (UNKNOWN; repo `shortcuts/` contains the `.lnk` files in the tree).
- Whether Desktop copies on flamingo / marchhare / ionos match commit `1a09848` or later SHAs.

---

## Optional script parameters

For operators who invoke `Watch-AgentHealth.ps1` with Bypass (not typical day-to-day):

- `-IrcHome` — must not be a forbidden home.
- `-Cwd` — explicit workspace.
- `-PollSeconds` (default 15), `-CrashBackoffSeconds` (default 20).
- `-LogPath` — alternate monitor log file.

Entry via `.cmd` always includes `-WatchWorker`; the outer process exits after spawning the hidden worker.
