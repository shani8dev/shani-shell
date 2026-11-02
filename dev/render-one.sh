#!/bin/sh
# render-one.sh — render ONE shani-shell surface for systematic review
# usage: render-one.sh <name> [ipc-command] [delay-seconds]
#   name:     output filename prefix
#   ipc-cmd:  IPC call to activate the surface (optional, e.g. "settingsCategory users")
#   delay:    seconds to wait after IPC before capture (default 1.5)
# env PRERUN: command run after the session is up and before the surface is
#   activated, for state that must exist first (e.g. a fake Mpris player:
#   'python3 /work/dev/fake-mpris.py "Title" "Artist" /tmp/cover.png &')
set -eu

OUTDIR="${1:-/renders}"
NAME="${2:-desktop}"
IPC="${3:-}"
DELAY="${4:-1.5}"
mkdir -p "$OUTDIR"
. /work/dev/session.sh

ipc() { eval "qs -p /work/shani ipc call shani $*" >/dev/null 2>&1; }
st() { timeout 5 qs -p /work/shani ipc call shani state 2>/dev/null; }

# wait for shell to load
i=0
until st >/dev/null 2>&1; do sleep 0.5; i=$((i+1)); [ $i -ge 60 ] && { echo "shell never loaded"; exit 1; }; done
echo "shell loaded"

# state that must be present before the surface is activated (PRERUN)
if [ -n "${PRERUN:-}" ]; then
    eval "$PRERUN"
    sleep 1.5
fi

# close everything first
eval "qs -p /work/shani ipc call shani closeAll" >/dev/null 2>&1
sleep 0.8

# activate the surface
if [ -n "$IPC" ]; then
    eval "qs -p /work/shani ipc call shani $IPC" >/dev/null 2>&1
fi
sleep "$DELAY"

# capture
grim "$OUTDIR/$NAME.png"
echo "captured $OUTDIR/$NAME.png"
