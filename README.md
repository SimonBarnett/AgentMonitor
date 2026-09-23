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

- **`new`** — fresh session id (no skill reload from a prior resume).
- **Without `new`** — resume the stored session.
- **`on`** (default) — visible watch console (IRC `irc-in` / `forward` lines print there) and visible agent TUI.
- **`off`** — neither window; monitor log still receives lines. One-shot `agent -p` forwards stay hidden in both modes.
- **`new` and `on`/`off`** may appear in either order on the main `.cmd`.

One-click `.cmd` files in the repo root pass **`-Windows on`** (visible watch console and agent TUI). Change `on` to `off` in those files to run headless.

On **Restricted** ExecutionPolicy, use these `.cmd` wrappers (`-ExecutionPolicy Bypass`). Do not rely on `.\Watch-AgentHealth.ps1` alone.

## IRC homes (watch seat only)

- Grok: `%USERPROFILE%\.agentic-irc-watch-grok`
- Cursor: `%USERPROFILE%\.agentic-irc-watch-cursor`

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
