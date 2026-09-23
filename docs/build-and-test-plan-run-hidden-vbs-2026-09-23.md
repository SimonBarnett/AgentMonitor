# Build/test plan: Run-Hidden.vbs no-console shortcuts

1. Read issue #66. Rebase the stale `issue-32-tui-launch-ps1` tip (`48f5665`) onto current `main` (`14198d5` or newer); resolve conflicts. Keep only the no-console VBS change unless already on main.
2. Shortcut `.cmd` files: `wscript` + `Run-Hidden.vbs`. Main `.cmd`: visible unless `off`.
3. Open or update PR linking #66. Do not push `main`. Do not merge. Do not stamp UAT.

## Checks

- Grep shortcut `.cmd`: `wscript.exe` + `Run-Hidden.vbs`. No `start "" powershell` on those four files.
- `Run-Hidden.vbs` uses `WScript.Shell.Run` style 0.
- Main `Watch-AgentHealth.cmd` still `-NoExit` when not `off`.
- PR `MERGEABLE` / `CLEAN` before PASS-nits merge.
