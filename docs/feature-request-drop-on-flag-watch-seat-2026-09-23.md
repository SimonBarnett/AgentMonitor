# FR: drop on flag; agent-monitor and watch-seat skills (issue #40)

https://github.com/SimonBarnett/AgentMonitor/issues/40

**MRB home:** [Issue #40](https://github.com/SimonBarnett/AgentMonitor/issues/40). **Land:** [PR #38](https://github.com/SimonBarnett/AgentMonitor/pull/38). No source PDF. No UAT.

Visible is the default. Launchers no longer pass `-Windows on`. `off` still hides both windows. Skills `agent-monitor` and `watch-seat` explain monitor vs watch-seat agent.

## LOCKED (issue #40)

1. Visible is the default. One-click launchers do not pass `-Windows on`.
2. `off` still hides the watch console and the agent TUI.
3. Skills `agent-monitor` and `watch-seat` live in `.grok/skills` and `.cursor/skills` and explain monitor vs watch-seat agent.
4. No UAT stamp.

## Gap vs `2eccf7e`

One-click `Watch-AgentHealth-*-*.cmd` files pass `-Windows on`. Playbook / README tell operators to change `on` to `off` for headless. There is no in-repo skill that states monitor vs watch-seat ownership.

## Acceptance

| ID | Gate |
|----|------|
| A1 | One-click launchers do not pass `-Windows on`. Default remains visible (watch console + agent TUI). |
| A2 | `off` still hides both windows. Monitor log still receives lines. |
| A3 | `agent-monitor` and `watch-seat` skills exist under `.grok/skills` and `.cursor/skills` and explain monitor vs watch-seat agent. |
| A4 | No UAT stamp. |

UNKNOWN: none named on the issue. Exact Desktop shortcut icon paths stay UNKNOWN (same as playbook).
