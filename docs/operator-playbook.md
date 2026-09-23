# AgentMonitor operator playbook

**Feature request:** [Issue #1](https://github.com/SimonBarnett/AgentMonitor/issues/1). **MRB:** [Issue #3](https://github.com/SimonBarnett/AgentMonitor/issues/3) (Bob chairs). This document does **not** stamp ready for human UAT.

AgentMonitor is `Watch-AgentHealth.ps1` plus `.cmd` launchers in this repo. It starts a **watch-seat** Grok or Cursor agent and forwards IRC traffic into that session. The agent still owns IRC per `agentic-irc` while the TUI is up. **Multiple clients can run on one box** (same pattern as talk seats `cursor` / `cursor-2`): each launch binds the next free slot (`.agentic-irc-watch-cursor`, `-2`, …) and does **not** restart or replace a live worker. When the TUI exits (any reason), the monitor writes `$IrcHome/agent.quit.request` (and `quit.req` for older agents) so `irc_agent` PARTs then QUITs **that slot only**. Do not reconnect the same client; start another `Watch-AgentHealth.cmd cursor new` for a new seat. The monitor does not PART talk-seat / bobiverse homes.

---

## What it does

| Responsibility | Owner |
|----------------|--------|
| Start `agent.exe` (Grok) or `agent.cmd` (Cursor) TUI | Monitor |
| Persist session id; resume without reloading all skills | Monitor (`~\.grok\agent-health\state-{grok\|cursor}.json`) |
| Connect to IRC (`irc_agent` + **own** `irc_listen` on this slot home) | Agent |
| Tail IRC debug log and inject `FROM` lines into the session | Monitor |
| Health-check; on TUI death QUIT that slot (no restart) | Monitor |
| Start, stop, or health-check `irc_listen` | **Not** the monitor |

The **watch worker** (`-WatchWorker`) runs the monitor loop. Visible by default (no `on` flag): the worker console stays visible and IRC `irc-in` / `forward` lines echo there; the Composer / Grok TUI opens in a normal window. **`-Windows off`** hides the worker and agent TUI; the log file still receives lines. One-shot `agent -p` forwards stay hidden.

---

## Grok vs Cursor

| Switch | Binary | IRC home default |
|--------|--------|------------------|
| `grok` | `agent.exe` | `%USERPROFILE%\.agentic-irc-watch-grok` (then `-2` … `-8`) |
| `cursor` | `agent.cmd` | `%USERPROFILE%\.agentic-irc-watch-cursor` (then `-2` … `-8`) |

Pass exactly one of `-Grok` / `-Cursor` (or `grok` / `cursor` on the main `.cmd`).

---

## Resume vs `new`

- **Resume** (default): if that slot is free, reuses its stored `sessionId`. If a client is already live, this launch takes the **next free slot** (new home / new nick) instead of restarting the live one.
- **`new`**: same slot bind, then a fresh `sessionId` on the chosen slot. For Cursor, only leftover nodes from the **previous session of that slot** and hung `forward-cursor.ps1` / orphan `worker-server` processes are pruned. Fleet `Git task` / other TUIs / other watch slots are left alone. If Composer exits, the watcher QUITs that slot and does **not** restart it; start another cmd for another client.

Examples (from repo root):

```bat
Watch-AgentHealth.cmd grok
Watch-AgentHealth.cmd grok new
Watch-AgentHealth.cmd cursor
Watch-AgentHealth.cmd cursor new
Watch-AgentHealth.cmd grok off
Watch-AgentHealth.cmd cursor new off
```

Visible by default. **No `on` flag.** `off` hides the watch console and agent TUI. `new` and `off` may be in either order.

One-click equivalents (no `-Windows on`; add `-Windows off` for headless):

| File | Effect |
|------|--------|
| `Watch-AgentHealth-Grok-Resume.cmd` | Grok, resume |
| `Watch-AgentHealth-Grok-New.cmd` | Grok, `new` |
| `Watch-AgentHealth-Cursor-Resume.cmd` | Cursor, resume |
| `Watch-AgentHealth-Cursor-New.cmd` | Cursor, `new` |

---

## IRC: own watch home only

**LOCKED** — use only the watch IRC homes:

- `%USERPROFILE%\.agentic-irc-watch-grok` (slot 1), `watch-grok-2` … `-8`
- `%USERPROFILE%\.agentic-irc-watch-cursor` (slot 1), `watch-cursor-2` … `-8`

**Forbidden** (monitor refuses `-IrcHome` pointing here):

- `%USERPROFILE%\.agentic-irc-cursor`
- `%USERPROFILE%\.agentic-irc-cursor-2`
- `%USERPROFILE%\.agentic-irc-bobiverse` (bobiverse Watch / talk-seat home)

Do not point the watch seat at another agent’s IRC home. Do not share `irc_listen` across slots.

### `irc.log` and `FROM` forwarding

1. The agent writes IRC debug lines to **`$IrcHome\irc.log`** (agent firehose).
2. The monitor tails **that slot's** `irc.log` only (does not duplicate `irc_listen` or TSR as a second listener). Each client starts its own `irc_listen` on its home. One shared listener would copy every PRIVMSG into every connected agent.
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

The main wrapper passes `-WatchWorker`. Visible launch runs the worker in the console (`-NoExit` so startup errors stay on screen). **`-Windows off`** starts a hidden worker (`-WindowStyle Hidden`).

---

## Logs and state (not in git)

| Item | Default location |
|------|------------------|
| Monitor log | `%USERPROFILE%\Desktop\Watch-AgentHealth\Watch-AgentHealth.log` (slot 2+ : `Watch-AgentHealth-N.log`) |
| Session state | `%USERPROFILE%\.grok\agent-health\state-{grok\|cursor}[-N].json` |
| Worker pid file | `%USERPROFILE%\.grok\agent-health\watch-worker-{grok\|cursor}[-N].pid` |

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
2. Persist session id per slot; `new` = next free slot + fresh session. Never restart a live client.
3. Monitor does not start/stop/health-check `irc_listen`.
4. Tail `$IrcHome/irc.log`; forward PRIVMSG as `FROM` into the agent session.
5. Own IRC home only (`.agentic-irc-watch-*`); forbidden homes listed above. Each client starts its own `irc_listen` on that home (shared listen duplicates traffic).
6. Launch via `.cmd` / `-ExecutionPolicy Bypass` on Restricted policy boxes.
7. Workspace `\ai` on D:..Z: unless `-Cwd` passed.
8. No UAT stamp; no `!bobiverse`.
9. Visible by default (no `on` flag). `-Windows off` hides both windows; one-shot `agent -p` forwards stay hidden.

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
- `-Windows off` — hide both terminals (default is visible).

Entry via `.cmd` always includes `-WatchWorker`. With `off`, the outer `.cmd` spawns a hidden worker and exits; otherwise the worker runs in the visible console.

**Skills** (what the monitor vs watch-seat agent do): `.grok/skills/agent-monitor/SKILL.md`, `.grok/skills/watch-seat/SKILL.md`.
