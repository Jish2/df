#!/bin/sh
# EarPods KEY DOWN. Stamp the press only — do not start Handy here.
# Karabiner decides tap vs hold; starting F18 on keydown races the hold
# threshold and cancels dictation as "music".

. /Users/jgoon/.config/karabiner/scripts/earpods-lib.sh

NOW=$(now_ms)
echo "$NOW" > "$DOWN_TS"
/bin/rm -f "$HOLD_FLAG" "$STARTED_ON_DOWN" "$MAYBE_RECONNECT" "$GHOST_FLAG"
mark_event
log "PRESS"
exit 0
