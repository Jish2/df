#!/bin/sh
# EarPods KEY DOWN. Stamp the press only — do not start dictation here.
# Karabiner decides tap vs hold; starting dictation on keydown races the
# hold threshold and cancels dictation as "music".

. /Users/jgoon/.config/karabiner/scripts/earpods-lib.sh

NOW=$(now_ms)
BUTTON=${1:-center}
echo "$NOW" > "$DOWN_TS"
echo "$BUTTON" > "$BUTTON_FILE"
mark_event
log "PRESS $BUTTON"
exit 0
