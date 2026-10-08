#!/bin/sh
# Hold or release F18 so Handy only ever sees push-to-talk.
# F18 is a normal key (kVK_F18 = 79). Unlike Fn, CGEvent can leave it down
# until we post key-up. Karabiner maps hardware Fn → F18 the same way.

STATE=/tmp/handy-fn-sim-held
# kVK_F18
KEYCODE=79

post_f18() {
    _down=$1
    /usr/bin/osascript -l JavaScript -e "
ObjC.import('CoreGraphics');
var src = \$.CGEventSourceCreate(1);
var ev = \$.CGEventCreateKeyboardEvent(src, $KEYCODE, $_down);
\$.CGEventPost(0, ev);
"
}

cmd=${1:-}
case "$cmd" in
    down)
        if [ -e "$STATE" ]; then
            echo already-down
            exit 0
        fi
        post_f18 true
        echo 1 > "$STATE"
        echo down
        ;;
    up)
        if [ ! -e "$STATE" ]; then
            echo already-up
            exit 0
        fi
        post_f18 false
        /bin/rm -f "$STATE"
        echo up
        ;;
    toggle)
        if [ -e "$STATE" ]; then
            exec "$0" up
        fi
        exec "$0" down
        ;;
    *)
        echo "usage: handy-fn-sim.sh down|up|toggle" >&2
        exit 2
        ;;
esac
