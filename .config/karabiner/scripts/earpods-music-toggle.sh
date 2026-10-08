#!/bin/sh
# EarPods HOLD → music. If dictation was started on keydown, cancel it.

. /Users/jgoon/.config/karabiner/scripts/earpods-lib.sh

STATE=/tmp/handy-earpods-music-last
NOW=$(now_ms)

/usr/bin/touch "$HOLD_FLAG"

if [ -e "$STARTED_ON_DOWN" ] || f18_is_held; then
    /bin/rm -f "$STARTED_ON_DOWN"
    handy_fn_release
    log "HELD_DOWN cancelled dictation → music"
else
    log "HELD_DOWN → music"
fi

if [ -f "$STATE" ]; then
    LAST=$(cat "$STATE" 2>/dev/null)
    if [ -n "$LAST" ] && [ $((NOW - LAST)) -lt 700 ]; then
        log "  music toggle skipped (debounce)"
        exit 0
    fi
fi
echo "$NOW" > "$STATE"

/opt/homebrew/bin/nowplaying-cli togglePlayPause
log "  music togglePlayPause sent"
exit 0
