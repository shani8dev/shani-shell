#!/bin/sh
# usage: greeter-test.sh [greeter-niri.kdl]
# Runs the greeter the way greetd does — a bare niri whose spawn line is
# `qs -c shani-greeter; niri msg action quit` — against dev/fake-greetd.py,
# types a wrong password and then the right one, and checks what greetd was
# sent. Prints `RESULT <check> PASS|FAIL` lines; exits non-zero on any FAIL.
# Default kdl: shani-pkgbuilds' shani-desktop-niri copy, as installed.
KDL="${1:-/etc/greetd/shani-niri-greeter.kdl}"

export XDG_RUNTIME_DIR=/run/user/0
# a laptop keyboard, as udev would list it: the screen keyboard waits to be asked for
export SHANI_INPUT_KINDS_TOOL=/work/bridge/input-kinds.py SHANI_UDEV_DB=/work/dev/udev-db/laptop.txt
mkdir -p "$XDG_RUNTIME_DIR" /work/out/logs
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
        --no-config --log=/work/out/logs/weston.log >/work/out/logs/weston.out 2>&1 &
    sleep 2
fi

# the greeter niri starts first-boot setup on a machine with no account
# (dev/setup-test.sh covers that); the login screen needs one to exist
getent passwd shani >/dev/null || useradd -m shani

export GREETD_SOCK="$XDG_RUNTIME_DIR/greetd.sock"
nohup python3 /work/dev/fake-greetd.py > /work/out/logs/greetd.log 2>&1 &
sleep 0.5

# the checkout, not a packaged copy, is what is under test
mkdir -p /root/.config/quickshell
ln -sfn /work/greeter /root/.config/quickshell/shani-greeter

SHANI_GREETER_WALLPAPER=/work/assets/shani-dark.jpg WAYLAND_DISPLAY=wayland-parent \
    nohup niri -c "$KDL" > /work/out/logs/greeter-niri.log 2>&1 &
NIRI_PID=$!

i=0
until pgrep -f 'qs -c shani-greeter' >/dev/null && [ -S "$XDG_RUNTIME_DIR/wayland-1" ] || [ "$i" -ge 40 ]; do
    sleep 0.25; i=$((i + 1))
done
sleep 2.5    # first frame + focus
export WAYLAND_DISPLAY=wayland-1
grim /work/out/shots/18-greeter.png 2>/dev/null || true

# the one account is already picked (nothing to type but the password); a wrong
# password first: greetd must see the failure, the greeter must recover
wtype nope -k Return; sleep 1.2
grim /work/out/shots/19-greeter-failed.png 2>/dev/null || true
# the user field keeps "shani"; only the password is typed again
wtype shani -k Return
i=0
while kill -0 "$NIRI_PID" 2>/dev/null && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done

LOG=/work/out/logs/greetd.log
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

# one more greeter run against fake-greetd: $1 a name, $2 what to type ("" = nothing),
# then the greetd conversation it had (env: whatever the case sets)
greet() {
    pkill -f fake-greetd.py 2>/dev/null || true
    while pgrep -f 'qs -c shani-greeter' >/dev/null || pgrep -x niri >/dev/null; do sleep 0.25; done
    rm -f "$XDG_RUNTIME_DIR"/wayland-1 "$XDG_RUNTIME_DIR"/wayland-1.lock
    nohup python3 /work/dev/fake-greetd.py > "/work/out/logs/greetd-$1.log" 2>&1 &
    sleep 0.5
    SHANI_GREETER_WALLPAPER=/work/assets/shani-dark.jpg WAYLAND_DISPLAY=wayland-parent nohup niri -c "$KDL" > "/work/out/logs/greeter-niri-$1.log" 2>&1 &
    NIRI_PID=$!
    i=0
    until pgrep -f 'qs -c shani-greeter' >/dev/null && [ -S "$XDG_RUNTIME_DIR/wayland-1" ] || [ "$i" -ge 40 ]; do
        sleep 0.25; i=$((i + 1))
    done
    sleep 2.5
    WAYLAND_DISPLAY=wayland-1 grim "/work/out/shots/19-greeter-$1.png" 2>/dev/null || true
    [ -n "$2" ] && WAYLAND_DISPLAY=wayland-1 wtype "$2" -k Return
    [ "$2" = "" ] && [ "$3" = enter ] && WAYLAND_DISPLAY=wayland-1 wtype -k Return
    i=0
    while kill -0 "$NIRI_PID" 2>/dev/null && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
    kill "$NIRI_PID" 2>/dev/null
    python3 -c '
import json, sys
print(" ".join(json.loads(l)["type"] for l in open(sys.argv[1]) if l.strip())[len("fake-greetd-up "):])
' "/work/out/logs/greetd-$1.log"
}
# ---- face (linux-hello): the session starts as soon as the user is known
export SHANI_GREETER_USER=shani SHANI_GREETER_FACE=1 SHANI_GREETER_FINGERPRINT=0
got=$(FAKE_FACE=match greet face "")
[ "$got" = "create_session start_session" ] && result greeter-face PASS || result greeter-face FAIL "got: $got"
# not recognised: the password, as ever
got=$(FAKE_FACE=miss greet face-miss shani)
[ "$got" = "create_session post_auth_message_response start_session" ] && result greeter-face-then-password PASS || result greeter-face-then-password FAIL "got: $got"
export SHANI_GREETER_FACE=0

# ---- fingerprint: Enter on an empty password asks for it (the flag pam_exec takes)
FRUN=/tmp/greeter-run; rm -rf "$FRUN"; mkdir -p "$FRUN"
export SHANI_GREETER_RUN="$FRUN" SHANI_GREETER_FINGERPRINT=1
got=$(SHANI_GREETER_KEYBOARD=1 greet finger "" enter)     # the screen keyboard shown too (19-greeter-finger.png)
[ "$got" = "create_session post_auth_message_response start_session" ] && [ ! -e "$FRUN/fingerprint" ] \
    && result greeter-fingerprint PASS || result greeter-fingerprint FAIL "got: $got"

pkill -f fake-greetd.py 2>/dev/null || true
[ "$fail" = 0 ]
