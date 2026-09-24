#!/bin/sh
# EarPods center-button RELEASE.
#   If the hold-flag is set → this press was a hold (music already toggled
#   at the 500ms threshold) — clear the flag, do nothing.
#   Otherwise → tap → toggle Handy dictation (start / stop + transcribe).

LOG=/tmp/handy-earpods-debug.log
FLAG=/tmp/handy-earpods-hold
REL_GUARD=/tmp/handy-earpods-last-release
NOW=$(/usr/bin/perl -MTime::HiRes=time -e 'printf("%d", time*1000)')

if [ -e "$FLAG" ]; then
    /bin/rm -f "$FLAG"
    echo "RELEASE → hold-flag cleared (no action)" >> "$LOG"
    exit 0
fi

# Collapse doubled event delivery: ignore a release within 300ms of the
# previous one (same physical press delivered twice).
if [ -f "$REL_GUARD" ]; then
    PREV=$(cat "$REL_GUARD" 2>/dev/null)
    if [ -n "$PREV" ] && [ $((NOW - PREV)) -lt 300 ]; then
        echo "RELEASE SKIPPED (collapse: $((NOW - PREV))ms after previous)" >> "$LOG"
        exit 0
    fi
fi
echo "$NOW" > "$REL_GUARD"

# TAP → toggle Handy dictation.
echo "RELEASE → tap → handy toggle" >> "$LOG"

HANDY=/Applications/Handy.app/Contents/MacOS/handy
if ! /usr/bin/pgrep -x handy >/dev/null 2>&1; then
    /usr/bin/open -a Handy
    exit 0
fi

# Record from the EarPods mic; only switches when needed so it never
# disrupts an active stream (no-op when they're unplugged).
if [ "$(/opt/homebrew/bin/SwitchAudioSource -c -t input 2>/dev/null)" != "EarPods Microphone" ]; then
    /opt/homebrew/bin/SwitchAudioSource -t input -s "EarPods Microphone" >/dev/null 2>&1 || true
fi

"$HANDY" --toggle-transcription
