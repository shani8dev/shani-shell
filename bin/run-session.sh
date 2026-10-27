#!/bin/sh
# usage: run-session.sh <niri-config.kdl> <blur 0|1>
# Boots weston(headless) -> niri -> wallpaper + demo window + Chronoa bridge
# (+ mock Chronoa) -> Quickshell.
set -e
CONFIG="$1"
BLUR="${2:-1}"

export XDG_RUNTIME_DIR=/run/user/0
export XDG_SESSION_TYPE=wayland
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# --- stop previous session ------------------------------------------------
pkill -f 'qs -c shani' 2>/dev/null || true
pkill -f 'chronoa-bridge.py' 2>/dev/null || true
pkill -f 'mock-chronoa.py' 2>/dev/null || true
pkill -x awww-daemon 2>/dev/null || true
pkill -x swaybg 2>/dev/null || true
pkill -x foot 2>/dev/null || true
pkill -x niri 2>/dev/null || true
sleep 0.6
rm -f "$XDG_RUNTIME_DIR"/wayland-1 "$XDG_RUNTIME_DIR"/wayland-1.lock "$XDG_RUNTIME_DIR"/niri.*.sock
rm -f /run/user/0/shani-chronoa.sock

# --- parent compositor ----------------------------------------------------
if ! pgrep -f 'weston --backend=headless' >/dev/null; then
    nohup weston --backend=headless-backend.so --shell=kiosk-shell.so \
        --width=1920 --height=1080 --socket=wayland-parent --idle-time=0 \
        --no-config --log=/work/logs/weston.log >/work/logs/weston.out 2>&1 &
    sleep 2
fi

# --- session bus ----------------------------------------------------------
if [ ! -s /work/dbus.addr ] || ! pgrep -x dbus-daemon >/dev/null; then
    dbus-daemon --session --fork --print-address=1 --print-pid=1 > /work/dbus.addr
fi
export DBUS_SESSION_BUS_ADDRESS=$(head -1 /work/dbus.addr)

# --- niri -----------------------------------------------------------------
WAYLAND_DISPLAY=wayland-parent nohup niri -c "$CONFIG" > /work/logs/niri.log 2>&1 &
i=0
while [ ! -S "$XDG_RUNTIME_DIR/wayland-1" ] && [ "$i" -lt 40 ]; do
    sleep 0.25
    i=$((i + 1))
done
if [ ! -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
    echo "niri failed to start"; tail -20 /work/logs/niri.log; exit 1
fi

export WAYLAND_DISPLAY=wayland-1

# --- wallpaper + demo window ---------------------------------------------
nohup awww-daemon > /work/logs/awww.log 2>&1 &
sleep 1
awww img /work/assets/wallpaper.png > /work/logs/awww-img.log 2>&1 || true
nohup foot -a shani-demo -o colors.background=111318 -o font=monospace:size=13 \
    -e /work/bin/demo-term.sh > /work/logs/foot.log 2>&1 &
sleep 1

# --- Chronoa --------------------------------------------------------------
nohup python3 /work/bin/mock-chronoa.py > /work/logs/mock.log 2>&1 &
sleep 0.7
nohup python3 /work/bin/chronoa-bridge.py > /work/logs/bridge.log 2>&1 &
sleep 0.7

# --- shell ----------------------------------------------------------------
mkdir -p /root/.config/quickshell
ln -sfn /work/shani /root/.config/quickshell/shani
SHANI_BLUR="$BLUR" nohup qs -c shani > /work/logs/qs.log 2>&1 &
sleep 3

echo "session up: config=$CONFIG blur=$BLUR"
