# Build and test plan: TUI-exit IRC PART+QUIT (issue #43)

**Spec:** `docs/feature-request-tui-exit-irc-quit-2026-09-23.md`

1. Read issue #43. Do not implement this on the issue #40 FIX PR.
2. Own branch from pulled `main`. Write `quit.req` (UTF-8 no BOM) on the watch home only; `irc_agent` PART then QUIT.
3. Skip forbidden homes. Do not stop python on another IRC home.
4. Evidence: log line for the request; `quit.req` path; no write under `.agentic-irc-cursor` / `cursor-2` / bobiverse Watch.
5. No UAT stamp.
