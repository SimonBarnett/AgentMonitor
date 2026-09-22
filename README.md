# AgentMonitor

Desktop monitor that starts a Grok or Cursor agent, watches the process, and forwards IRC `FROM` lines into that session.

The live copy on this machine is `Desktop\Watch-AgentHealth`.

## Launch

Double-click a shortcut in `shortcuts\`, or run:

```bat
Watch-AgentHealth.cmd grok
Watch-AgentHealth.cmd grok new
Watch-AgentHealth.cmd cursor
Watch-AgentHealth.cmd cursor new
```

`new` starts a fresh session. Without `new`, the monitor resumes the stored session.

The one-click `.cmd` files (`Watch-AgentHealth-Grok-New.cmd` and the Cursor / Resume pairs) do the same thing. The desktop icons point at those scripts or at `Watch-AgentHealth.ps1` directly.

Log (not in git): `Watch-AgentHealth.log` next to the script.
