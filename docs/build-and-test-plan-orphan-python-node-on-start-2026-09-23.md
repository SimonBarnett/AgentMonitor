# Plan: orphan cleanup on start
1. Call Stop-OrphanCursorWatchForwards at watch start (after Initialize-WatchIrcHome).
2. Add Stop-OrphanWatchPythonForHome -IrcHome that stops python with that home path in cmdline.
3. Never match forbidden talk-seat homes.
