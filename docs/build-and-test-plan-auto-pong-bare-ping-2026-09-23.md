# Build/test plan: auto-pong bare PING

1. Add `Test-BareIrcPing` / handle in `Send-IrcLineToSession` before forward.
2. On bare ping: write outbox PRIVMSG pong; log; do not Start-Process agent.
3. Keep Test-DropIrcLine for POINT/DIGEST; do not re-break ping me (#7).
4. Tests: parse fixtures for bare vs ping me; assert outbox write helper.
