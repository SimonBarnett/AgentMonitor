# FR: drop on flag; agent-monitor and watch-seat skills (issue #40)

https://github.com/SimonBarnett/AgentMonitor/issues/40

**MRB:** [Issue #55](https://github.com/SimonBarnett/AgentMonitor/issues/55) (Bob chairs). **Land:** [PR #38](https://github.com/SimonBarnett/AgentMonitor/pull/38) (`b7e3db5`, merged 2026-09-23). [PR #53](https://github.com/SimonBarnett/AgentMonitor/pull/53) (`65861878`) is a closed leftover docs FIX; do not reopen or merge. [PR #49](https://github.com/SimonBarnett/AgentMonitor/pull/49) (`89f30f85`) reverted `#43` product on a leftover FIX branch; stays **closed**; do not merge. [PR #56](https://github.com/SimonBarnett/AgentMonitor/pull/56) (`dd41cfa`) and [PR #58](https://github.com/SimonBarnett/AgentMonitor/pull/58) (`67d368b`) are closed process-only intake; do not merge. [Issue #50](https://github.com/SimonBarnett/AgentMonitor/issues/50) closed; no FIX. No UAT.

Visible is the default after #34 TUI launch. This FR drops the `on` flag and parks two skills.

## LOCKED

1. Visible is the default. Launchers no longer pass `-Windows on`.
2. `off` still hides both windows.
3. Skills `agent-monitor` and `watch-seat` (`.grok/skills` and `.cursor/skills`) explain monitor vs watch-seat agent (TUI via prompt file, prune rules, IRC homes).

## Gap vs `2eccf7e` (main after #37)

Historical only: launchers passed `-Windows on`; no in-repo skill pack. Closed on `main` via PR #38 (`b7e3db5`). Issue #43 (`07abe04`, TUI-exit PART+QUIT) is separate product on `main` (docs land [PR #47](https://github.com/SimonBarnett/AgentMonitor/pull/47)); not a #40 MUST.

## Acceptance

| ID | Gate |
|----|------|
| A1 | `Watch-AgentHealth-Cursor-New.cmd` has no `-Windows on`. |
| A2 | `Watch-AgentHealth.cmd cursor` still opens a visible console + TUI. |
| A3 | `Watch-AgentHealth.cmd cursor off` stays hidden. |
| A4 | Skills `agent-monitor` and `watch-seat` exist under `.grok/skills` and `.cursor/skills`. |
| A5 | No UAT stamp. |
