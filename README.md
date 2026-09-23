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
Watch-AgentHealth.cmd cursor new
Watch-AgentHealth.cmd grok off
Watch-AgentHealth.cmd cursor new off
```

- **`new`** — next free slot, fresh session id (does not restart a live client).
- **Without `new`** — next free slot; resume that slot’s stored session if the slot was free.
- Visible by default (watch console + agent TUI). **No `on` flag.**
- **`off`** — neither window; monitor log still receives lines. One-shot `agent -p` forwards stay hidden.
- **`new` and `off`** may appear in either order on the main `.cmd`.

One-click `.cmd` files in the repo root do not pass `-Windows`. Add `-Windows off` (or `off` on the main `.cmd`) to run headless.

**Skills:** `.grok/skills/agent-monitor` and `.grok/skills/watch-seat` (also under `.cursor/skills/`).

On **Restricted** ExecutionPolicy, use these `.cmd` wrappers (`-ExecutionPolicy Bypass`). Do not rely on `.\Watch-AgentHealth.ps1` alone.

## IRC homes (watch seat only)

- Grok: `%USERPROFILE%\.agentic-irc-watch-grok` then `watch-grok-2` …
- Cursor: `%USERPROFILE%\.agentic-irc-watch-cursor` then `watch-cursor-2` …

Do not use talk-seat / bobiverse Watch homes (see playbook).

## Log (not in git)

Default monitor log: `%USERPROFILE%\Desktop\Watch-AgentHealth\Watch-AgentHealth.log`

Session state: `%USERPROFILE%\.grok\agent-health\state-grok.json` or `state-cursor.json`.

## Repo docs

| Document | Purpose |
|----------|---------|
| [docs/operator-playbook.md](docs/operator-playbook.md) | Full operator contract |
| [docs/feature-request-document-agentmonitor-2026-09-23.md](docs/feature-request-document-agentmonitor-2026-09-23.md) | FR / acceptance |
| [docs/build-and-test-plan-document-agentmonitor-2026-09-23.md](docs/build-and-test-plan-document-agentmonitor-2026-09-23.md) | Build plan for this doc work |
