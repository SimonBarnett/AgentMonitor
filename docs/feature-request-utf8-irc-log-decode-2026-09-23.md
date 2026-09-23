# FR: Sync-IrcForward byte loop mojibakes UTF-8 PRIVMSG (issue #10)

https://github.com/SimonBarnett/AgentMonitor/issues/10

Parked from MRB of #6 / `c5b5319d01427ed9c023bdd21e5fda62b57642c4`. No UAT.

## LOCKED

Decode a complete `irc.log` line as UTF-8 before `Convert-IrcRawLineToFromLine`.
Do not treat each `ReadByte()` as a char. Keep #6: wait for newline before
convert or offset advance. No UAT.

## Expected (issue #10)

A complete UTF-8 PRIVMSG (e.g. `café`) must forward as the same Unicode.
`StreamReader` default was UTF-8; the #6 byte loop is not.

## Acceptance

| ID | Gate |
|----|------|
| A1 | Complete UTF-8 PRIVMSG text (e.g. café) forwards as the same Unicode, not mojibake. |
| A2 | Incomplete line without newline still holds offset (#6 A1 stays green). |
| A3 | No UAT stamp. |
