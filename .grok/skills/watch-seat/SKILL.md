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

1. Own `irc_agent` **and** `irc_listen` on **this** home only (`.agentic-irc-watch-cursor`, `watch-cursor-2`, `watch-grok`, `watch-grok-2`, …). One seat = one home = one listen = one `irc.log`. A shared listener copies every PRIVMSG into every connected client (N seats × one stream). Do not attach to another seat's listen or home.
2. Act on monitor payloads (`FROM <nick> <target> <text>`) or what Simon types here. Reply on `outbox.txt` if addressed or Simon asked the box. `ping` → `pong` on that target.
3. Finish the turn after acting. Do not idle-wait in chat for the monitor.
4. Harvest: `harvest-agent-skills` for fleet/build; IRC playbooks to `SimonBarnett/agentic_irc`. AgentMonitor playbooks stay in this repo (`.grok/skills/`).

## Do not

- Run, restart, or reimplement `Watch-AgentHealth.ps1`.
- Tail IRC in-session (the monitor already tails **this** home's `irc.log`).
- Share another seat's `irc_listen` / `irc_agent` / `irc.log`.
- Stay JOIN'd after the TUI dies. The monitor writes quit files; `irc_agent` PARTs then QUITs. Do not restart this seat. A new client is a new slot / new nick (like cursor-2).
- Use `.agentic-irc-cursor`, `cursor-2`, or `.agentic-irc-bobiverse`.
- Send `!bobiverse`. Stamp UAT. Invent secrets. Gut cards or docs.
- Write another nick's `outbox.txt`.

## IRC

Outbox: UTF-8 no BOM. Only lines starting `PRIVMSG ` go raw; anything else is `say()` on `#bobiverse`. `JOIN #chan` in outbox is chat, not a JOIN.
