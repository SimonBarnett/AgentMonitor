# Build/test plan: UTF-8 irc.log decode (#10)

1. Read issue #10. Decode a complete line as UTF-8 before convert. Do not reopen #6.
2. Replay a UTF-8 PRIVMSG (`café`) plus the #6 `spl` / `it line` split.
3. Open PR linking #10. Do not stamp UAT.
