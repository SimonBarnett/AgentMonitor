# Build/test plan: shortcuts/.lnk target .cmd (issue #68)

1. Read https://github.com/SimonBarnett/AgentMonitor/issues/68 and `docs/feature-request-lnk-target-cmd-2026-09-23.md`.
2. Point these five `shortcuts/*.lnk` at the matching `Watch-AgentHealth-*-*.cmd` wrapper (same pattern as `Watch AgentHealth - *.lnk`). Do **not** target `powershell.exe` or `wscript.exe`.
   - `Watch-Agent Cursor New.lnk`
   - `Watch-Agent Cursor Resume.lnk`
   - `Watch-Agent Grok New.lnk`
   - `Watch-Agent Grok Resume.lnk`
   - `Watch-AgentHealth-Grok-Resume.lnk`
3. Leave VBS / no-console launch in the `.cmd` files (`Run-Hidden.vbs` from #66). Do not put VBS argv on the `.lnk`.
4. Do not change the meaning of the four shortcut `.cmd` files or `Run-Hidden.vbs`.
5. Open a PR linking #68. Do not push `main`. Do not merge. Do not stamp UAT.

## Checks

| ID | Gate |
|----|------|
| A1 | The five `.lnk` files above target the matching `.cmd`, not `powershell.exe`. |
| A2 | No `shortcuts/*.lnk` has target `wscript.exe` or `powershell.exe`. |
| A3 | Four shortcut `.cmd` files and `Run-Hidden.vbs` unchanged in meaning (#66 A1–A2 stay green). |
| A4 | No UAT stamp. |

Inspect `.lnk` targets with a shortcut COM/`WScript.Shell` read (or equivalent). Do not rewrite `.lnk` to `wscript.exe` + Desktop `Run-Hidden.vbs` (that is SHA `48f5665`, not this FR).
