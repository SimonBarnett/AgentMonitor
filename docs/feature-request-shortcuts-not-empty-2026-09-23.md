# FR: operator playbook says shortcuts/ is empty (issue #8)

https://github.com/SimonBarnett/AgentMonitor/issues/8

## LOCKED

Say `shortcuts/` contains the `.lnk` files in the tree. Keep UNKNOWN
whether flamingo / marchhare / ionos Desktop copies match a given SHA.
Do not say the directory is empty. No UAT.

## Acceptance

| ID | Gate |
|----|------|
| A1 | `docs/operator-playbook.md` no longer claims `shortcuts/` is empty. |
| A2 | Per-machine Desktop copies stay UNKNOWN. |
| A3 | No UAT stamp. |
