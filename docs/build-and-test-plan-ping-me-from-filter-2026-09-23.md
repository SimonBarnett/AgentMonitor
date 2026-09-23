# Build/test plan: ping me FROM filter (#7)

1. Read issue #7. Stop dropping ordinary FROM text that contains `ping`.
2. Confirm `Test-DropIrcLine` / convert: `ping me` forwards; server PING still dropped.
3. Open PR linking #7. Do not stamp UAT.
