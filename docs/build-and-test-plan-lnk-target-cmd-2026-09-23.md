# Build and test plan: .lnk target .cmd (#68)

## MUST
1. Five listed `shortcuts/*.lnk` target matching `Watch-AgentHealth-*-*.cmd`, not `powershell.exe`.
2. No `shortcuts/*.lnk` targets `powershell.exe` or `wscript.exe`.
3. Four shortcut `.cmd` files and `Run-Hidden.vbs` (if present) unchanged in meaning.
4. No UAT stamp.

## Checks
- COM-read each `.lnk` TargetPath basename is `*.cmd`.
- `git diff` does not change `Watch-AgentHealth*.cmd` or `Run-Hidden.vbs`.
