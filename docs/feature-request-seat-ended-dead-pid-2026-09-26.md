# FR: seat ended when nick/seat PID dead

See https://github.com/SimonBarnett/AgentMonitor/issues/136

Ensure writes live seat= before irc_agent start; re-nicks when suffix PID is dead; prefers TUI rootPid.
