#!/bin/sh
# usage: greeter-test.sh [greeter-niri.kdl]
# Runs the greeter the way greetd does — a bare niri whose spawn line is
# `qs -c shani-greeter; niri msg action quit` — against dev/fake-greetd.py,
# types a wrong password and then the right one, and checks what greetd was
# sent. Prints `RESULT <check> PASS|FAIL` lines; exits non-zero on any FAIL.
# Default kdl: shani-pkgbuilds' shani-desktop-niri copy, as installed.
KDL="${1:-/etc/greetd/shani-niri-greeter.kdl}"

export XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR" /work/logs
chmod 700 "$XDG_RUNTIME_DIR"
fail=0
result() {
    echo "RESULT $1 $2"
    [ "$2" = PASS ] || fail=1
}

pkill -f fake-greetd.py 2>/dev/null || true
pkill -f 'qs -c shani-greeter' 2>/dev/null || true
pkill -x niri 2>/dev/null || true
sleep 0.5
rm -f "$XDG_RUNTIME_DIR"/wayland-1 "$XDG_RUNTIME_DIR"/wayland-1.lock

if ! pgrep -f 'weston --backend=headless' >/dev/null; then
    nohup weston --backend=headless-backend.so --shell=kiosk-shell.so \
        --width=1920 --height=1080 --socket=wayland-parent --idle-time=0 \
        --no-config --log=/work/logs/weston.log >/work/logs/weston.out 2>&1 &
    sleep 2
fi

export GREETD_SOCK="$XDG_RUNTIME_DIR/greetd.sock"
nohup python3 /work/dev/fake-greetd.py > /work/logs/greetd.log 2>&1 &
sleep 0.5

# the checkout, not a packaged copy, is what is under test
mkdir -p /root/.config/quickshell
ln -sfn /work/greeter /root/.config/quickshell/shani-greeter

SHANI_GREETER_WALLPAPER=/work/assets/wallpaper.png WAYLAND_DISPLAY=wayland-parent \
    nohup niri -c "$KDL" > /work/logs/greeter-niri.log 2>&1 &
NIRI_PID=$!

i=0
until pgrep -f 'qs -c shani-greeter' >/dev/null && [ -S "$XDG_RUNTIME_DIR/wayland-1" ] || [ "$i" -ge 40 ]; do
    sleep 0.25; i=$((i + 1))
done
sleep 2.5    # first frame + focus
export WAYLAND_DISPLAY=wayland-1
grim /work/docs/shots/18-greeter.png 2>/dev/null || true

# wrong password first: greetd must see the failure, the greeter must recover
wtype shani -k Return; sleep 0.3
wtype nope -k Return; sleep 1.2
grim /work/docs/shots/19-greeter-failed.png 2>/dev/null || true
# the user field keeps "shani"; only the password is typed again
wtype shani -k Return
i=0
while kill -0 "$NIRI_PID" 2>/dev/null && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done

LOG=/work/logs/greetd.log
types=$(python3 -c '
import json, sys
print(" ".join(json.loads(l)["type"] for l in open(sys.argv[1]) if l.strip())[len("fake-greetd-up "):])
' "$LOG")
# after a failed auth the greetd protocol wants the session cancelled before
# a new one is created; Quickshell does that itself
want="create_session post_auth_message_response cancel_session create_session post_auth_message_response start_session"
[ "$types" = "$want" ] && result greeter-conversation PASS || {
    result greeter-conversation FAIL; echo "  got:  $types"; echo "  want: $want"; }
python3 -c '
import json, sys
starts = [m for m in map(json.loads, filter(str.strip, open(sys.argv[1]))) if m["type"] == "start_session"]
sys.exit(0 if [m["cmd"] for m in starts] == [["niri-session"]] else 1)
' "$LOG" && result greeter-launch-cmd PASS || result greeter-launch-cmd FAIL
pgrep -f 'qs -c shani-greeter' >/dev/null && result greeter-qs-exits FAIL || result greeter-qs-exits PASS
kill -0 "$NIRI_PID" 2>/dev/null && result greeter-niri-exits FAIL || result greeter-niri-exits PASS

f=$(find /root/.local/state/quickshell -name last-user 2>/dev/null | head -1)
[ -n "$f" ] && [ "$(cat "$f")" = shani ] && result greeter-remembers-user PASS || result greeter-remembers-user FAIL "${f:-no state file}"

pkill -f fake-greetd.py 2>/dev/null || true
[ "$fail" = 0 ]
