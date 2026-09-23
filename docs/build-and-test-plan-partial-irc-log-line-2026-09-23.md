# Build/test plan: partial irc.log line (#6)

1. Read issue #6. Fix `Sync-IrcForward` so a short read at EOF is not a finished line.
2. Replay the observed split (`spl` then `it line`). Prefix not forwarded; completed line forwarded once.
3. Open PR linking #6. Do not stamp UAT.
