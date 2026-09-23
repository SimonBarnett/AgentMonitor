# Build/test plan: shortcut hidden background

1. Read issue #61 and PR #60. Rebase onto current `main` if the branch is diverged; resolve conflicts.
2. Shortcut `.cmd` files: hidden start. Main `.cmd`: visible unless `off`.
3. Open or update PR linking #61. Do not push `main`. Do not merge. Do not stamp UAT.

## Checks

- Grep shortcut `.cmd` for `WindowStyle Hidden` (or `-Windows off` via hidden powershell).
- Main `Watch-AgentHealth.cmd` still uses visible `-NoExit` when not `off`.
- PR mergeable `MERGEABLE` / `CLEAN` before MRB PASS-nits merge.
