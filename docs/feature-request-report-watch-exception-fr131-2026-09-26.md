# FR #131: deterministic exceptions must gh-issue (no LLM)

**Issue:** https://github.com/SimonBarnett/AgentMonitor/issues/131

`Report-WatchException` opens `SimonBarnett/AgentMonitor` issues via `gh issue create` only.
Wired from `Send-IrcLineToSession`, watch loop, and fatal catch. Dedupe by fingerprint for 12h.
