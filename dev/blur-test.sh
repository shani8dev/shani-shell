#!/bin/sh
# usage: blur-test.sh <name> <config.kdl> <blur 0|1>
# Boots a session, opens the Chronoa card over the terminal + wallpaper, and
# saves a full screenshot plus a crop where the card overlaps sharp text.
set -e
NAME="$1"; CONFIG="$2"; BLUR="$3"

/work/dev/run-session.sh "$CONFIG" "$BLUR" >/dev/null

export XDG_RUNTIME_DIR=/run/user/0
export WAYLAND_DISPLAY=wayland-1
qs -c shani ipc call shani openChronoa >/dev/null 2>&1 || true
sleep 1.2

/work/dev/shot.sh "/work/docs/shots/$NAME.png" >/dev/null
# the card's left half sits over the terminal's text - that is where blur shows
magick "/work/docs/shots/$NAME.png" -crop 420x380+540+250 +repage \
    "/work/docs/shots/$NAME-crop.png"
# and the bar's left end sits over the wallpaper
magick "/work/docs/shots/$NAME.png" -crop 560x44+0+6 +repage \
    "/work/docs/shots/$NAME-bar.png"
echo "$NAME done"
