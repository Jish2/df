#!/bin/sh
# EarPods KEY DOWN. Start Handy immediately on a normal tap so we don't
# wait for button-up. Hold ≥250ms cancels that start and toggles music.

. /Users/jgoon/.config/karabiner/scripts/earpods-lib.sh

NOW=$(now_ms)
GAP=$(idle_gap_ms)
echo "$NOW" > "$DOWN_TS"
/bin/rm -f "$STARTED_ON_DOWN" "$MAYBE_RECONNECT" "$GHOST_FLAG"

# First event after a long idle (plug-in) can be a USB ghost. Don't start
# Handy until release proves it was a real tap.
if [ "$GAP" -ge "$IDLE_GAP_MS" ]; then
    /usr/bin/touch "$MAYBE_RECONNECT"
    mark_event
    log "PRESS idle ${GAP}ms → wait for release"
    exit 0
fi

mark_event

if f18_is_held; then
    log "PRESS already recording (stop on release unless hold)"
    exit 0
fi

RESULT=$(handy_f18_down)
/usr/bin/touch "$STARTED_ON_DOWN"
switch_earpods_mic_bg
log "PRESS F18 down ($RESULT)"
exit 0
