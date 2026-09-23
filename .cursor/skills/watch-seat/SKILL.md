---
name: watch-seat
description: >
  Behaviour for the Grok or Cursor agent inside an AgentMonitor watch TUI.
  Use when this session is the watch seat, monitor forwards FROM lines,
  .agentic-irc-watch-cursor / watch-grok, or Simon says watch seat / AgentMonitor agent.
---

# Watch seat

You sit in the Composer / Grok TUI that **Watch-AgentHealth** started. Skill `agent-monitor` is the monitor contract.

## Do

1. Own `irc_agent` on **this** home only (`.agentic-irc-watch-cursor` or `.agentic-irc-watch-grok`). `irc_listen` per `agentic-irc`.
2. Act on monitor payloads (`FROM <nick> <target> <text>`) or what Simon types here. Reply on `outbox.txt` if addressed or Simon asked the box. `ping` → `pong` on that target.
3. Finish the turn after acting. Do not idle-wait in chat for the monitor.
4. Harvest: `harvest-agent-skills` for fleet/build; IRC playbooks to `SimonBarnett/agentic_irc`. AgentMonitor playbooks stay in this repo (`.grok/skills/`).

## Do not

- Run, restart, or reimplement `Watch-AgentHealth.ps1`.
- Tail IRC in-session (the monitor already tails `irc.log`).
- Stay JOIN'd after the TUI dies. The monitor writes `quit.req`; `irc_agent` PARTs then QUITs before any reconnect.
- Use `.agentic-irc-cursor`, `cursor-2`, or `.agentic-irc-bobiverse`.
- Send `!bobiverse`. Stamp UAT. Invent secrets. Gut cards or docs.
- Write another nick's `outbox.txt`.

## IRC

Outbox: UTF-8 no BOM. Only lines starting `PRIVMSG ` go raw; anything else is `say()` on `#bobiverse`. `JOIN #chan` in outbox is chat, not a JOIN.
