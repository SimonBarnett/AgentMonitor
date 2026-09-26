# FR: IRC PART seat ended from stale coordinator agent=

**Root cause:** `talk_seat_pid.coordinator_seat_pid` prefers `agent=` over `seat=`.
Watch-AgentHealth wrote `agent=<irc_agent pid>`. On restart, a new irc_agent read a
**dead** `agent=` and PART'd `seat ended` while the TUI (`seat=`) was still alive.

**Fix:** `Write-WatchCoordinatorPid` sets `agent=$SeatPid` (live TUI/host) and stores
the python pid in `irc_agent=`. `Write-WatchIrcHealthSnapshot` logs health ticks /
disconnect / ensure for diagnosis.

**Logging:** `irc-health tag=...` lines in Watch-AgentHealth.log.
