# FR #152: Wake payload puts ASSIGN before ACK/DONE reminder

## Problem

`Format-WatchWakeText` appended the full `FROM` after `DONE ends at the URL:`,
so the model treated the Jeeves assign as a wire-format example. Transcript
preview (120 chars) cut before the assign.

## Fix

1. Order: `FOR YOU` → `ASSIGN:` + full FROM → ACK/DONE reminder.
2. Grok wakes use `--prompt-file` (`forward-grok.prompt.txt`), same idea as Cursor.
3. Addressed FROM lines are not MaxLen-truncated.
4. Transcript preview length 500 so operators see the assign.
5. Test `AM152`.
