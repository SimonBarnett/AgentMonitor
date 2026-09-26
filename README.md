# AgentMonitor

Desktop monitor that starts a Grok or Cursor **watch-seat** agent, watches the process, and forwards IRC `FROM` lines into that session. The agent still connects to IRC per `agentic-irc`; the monitor tails `irc.log` only.

**Operator documentation:** [docs/operator-playbook.md](docs/operator-playbook.md) (launch, resume vs `new`, IRC homes, Restricted ExecutionPolicy, LOCKED vs UNKNOWN).

**Feature request:** [Issue #1](https://github.com/SimonBarnett/AgentMonitor/issues/1). **MRB:** [Issue #3](https://github.com/SimonBarnett/AgentMonitor/issues/3). This repo does not stamp ready for human UAT.

## Launch

From a copy of this repo (or your deployed `Watch-AgentHealth` folder), double-click a shortcut if you have one, or run:

```bat
Watch-AgentHealth.cmd grok
Watch-AgentHealth.cmd grok new
Watch-AgentHealth.cmd cursor
Watch-AgentHealth.cmd cursor resume
Watch-AgentHealth.cmd grok off
Watch-AgentHealth.cmd cursor new off
```

- **Default / `new`** — fresh session id + full skills + seed prompt (CAST IRON for all Desktop links and tray Agents clicks).
- **`resume`** — rare recovery only; reuses the stored session id. Desktop / tray links never use this.
- Visible by default (watch console + agent TUI). **No `on` flag.**
- **`off`** — neither window; monitor log still receives lines. One-shot `agent -p` forwards stay hidden.
- **`new` / `resume` and `off`** may appear in either order on the main `.cmd`.

One-click `.cmd` files and Desktop shortcuts start in the background (`-Windows off`) and **always** pass `-New`. Legacy `*Resume*` shortcut names still launch a new session. Refresh Desktop icons with `tools\Publish-DesktopShortcuts.ps1` (IconLocation = agent `.exe`). Repo `shortcuts/*.lnk` are generated per machine and gitignored, so publishing never dirties the clone.

**Skills:** `.grok/skills/agent-monitor` and `.grok/skills/watch-seat` (also under `.cursor/skills/`).

On **Restricted** ExecutionPolicy, use these `.cmd` wrappers (`-ExecutionPolicy Bypass`). Do not rely on `.\Watch-AgentHealth.ps1` alone.

## IRC homes (watch seat only)

- Grok: `%USERPROFILE%\.agentic-irc-watch-grok`
- Cursor: `%USERPROFILE%\.agentic-irc-watch-cursor`

Do not use talk-seat / bobiverse Watch homes (see playbook).

**Channels:** each watch seat JOINs its own `#{machine}` only (never `#bobiverse` / `#agentic_irc`).

**`!bored` (FR #100):** the monitor posts `PRIVMSG #{machine} :!bored` on seat start, right after the seat's `DONE`, and every few minutes while idle — never while busy (open ACK or pending `agent -p`). No LLM turn. Jeeves assigns the next job; the seat ACKs.

**Loop seat (FR #103):** continuous non-job agents (e.g. ce-dayworks) use `-SeatType loop -Channel '#ce-priority-dev1' -Nick dayworks-dev1` (or `-NoBored`). That suppresses every `!bored` and the fleet ACK/DONE brief. Nick must **not** be `{machine}-{pid}` so Jeeves never assigns.

**Forward dedupe (FR #105):** identical IRC `FROM` lines are skipped for `-ForwardDedupeSeconds` (default **60**), then forwarded again. Every skip is logged (`forward skipped (duplicate within …)`).

**Wake lifecycle (FR #91):** at most one hidden `-p` wake per session. Further FROM lines queue
(coalesce duplicates). `-WakeTimeoutSeconds` (default **1800**) kills hung wakes (`wake timeout`).
On monitor start, orphan `-p` wakes whose parent is dead are reaped; interactive TUI (no `-p`) is never touched.

**Visible IRC wakes (FR #90 Option B):** each hidden `agent -p` / Cursor `-p` forward is logged to
`%USERPROFILE%\.grok\agent-health\watch-<kind>-<slot>\seat-wake-transcript.log` with
`wake start … pid=` and later `wake end … exit=`. With `-Windows on`, the monitor opens a
**Watch seat IRC wake transcript** console that tails that file so the seat does not look idle
while work runs off-screen. The Composer/Grok TUI still does not reload those turns in-place
(no keystroke injection).

## Log (not in git)

Default monitor log: `%USERPROFILE%\Desktop\Watch-AgentHealth\Watch-AgentHealth.log`

Session state: `%USERPROFILE%\.grok\agent-health\state-grok.json` or `state-cursor.json`.

## Repo docs

| Document | Purpose |
|----------|---------|
| [docs/operator-playbook.md](docs/operator-playbook.md) | Full operator contract |
| [docs/feature-request-document-agentmonitor-2026-09-23.md](docs/feature-request-document-agentmonitor-2026-09-23.md) | FR / acceptance |
| [docs/build-and-test-plan-document-agentmonitor-2026-09-23.md](docs/build-and-test-plan-document-agentmonitor-2026-09-23.md) | Build plan for this doc work |
