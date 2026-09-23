# Build/test plan: drop on flag + skills (#40)

1. Read issue #40. A1–A5 are on `main` via PR #38 (`b7e3db5`). MRB #55 required fixes are process-only: leave PR #53, PR #49, PR #56, and PR #58 closed; do not revert `07abe04` off `main`; no further #40 product change; no #40/#50 FIX worker.
2. Default remains visible. Do not require `-Windows on`.
3. `off` still hides both windows.
4. Do not stamp UAT. Bob chairs MRB on #55; implementer does not merge.
5. A1–A5 are on `main` via PR #38. MRB #55 records the closed PR #53 merge gate; no product delta for this FR MUST.

## Checks

- Grep launchers: no `-Windows on`.
- `off` path still hides the watcher console and TUI.
- Skills `agent-monitor` and `watch-seat` present in `.grok/skills` and `.cursor/skills`.
- PR #49, PR #53, PR #56, and PR #58 stay closed. `main` retains `Disconnect-WatchIrc` / `quit.req` (issue #43).
