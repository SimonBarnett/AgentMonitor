# Build/test plan: drop on flag; agent-monitor and watch-seat skills (#40)

1. Read issue #40 and this FR. Visible stays the default. Do not pass `-Windows on` from one-click launchers.
2. Keep `off` hiding both windows. Land `agent-monitor` and `watch-seat` skills in `.grok/skills` and `.cursor/skills`.
3. Open a PR linking the issue. Do not stamp UAT.

## Checks

- Grep: one-click `Watch-AgentHealth-*-*.cmd` files do not contain `-Windows on`.
- Grep: `Watch-AgentHealth.cmd` still accepts `off` and hides both windows.
- Files exist: `.grok/skills/agent-monitor/SKILL.md`, `.grok/skills/watch-seat/SKILL.md`, `.cursor/skills/agent-monitor/SKILL.md`, `.cursor/skills/watch-seat/SKILL.md`.
