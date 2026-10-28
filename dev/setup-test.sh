#!/bin/sh
# usage: setup-test.sh [greeter-niri.kdl]
# First-boot setup, end to end, the way greetd runs it: the greeter niri on a
# machine with no account starts `qs -c shani-setup`; the wizard is walked page
# by page (IPC, as a person would click), creates the account with the real
# bridge/first-account.py (as root here — pkexec in the image) and signs in
# through dev/fake-greetd.py. Then the same niri config on the now set-up
# machine must start the login screen instead, and the helper must refuse.
KDL="${1:-/etc/greetd/shani-niri-greeter.kdl}"

export XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR" /work/logs /work/docs/shots
chmod 700 "$XDG_RUNTIME_DIR"
fail=0
result() {
    echo "RESULT $1 $2 ${3:+($3)}"
    [ "$2" = PASS ] || fail=1
}

if getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ { f = 1 } END { exit !f }'; then
    echo "this container already has an account: the first-boot path cannot be tested"; exit 1
fi

nohup weston --backend=headless-backend.so --shell=kiosk-shell.so \
    --width=1920 --height=1080 --socket=wayland-parent --idle-time=0 \
    --no-config --log=/work/logs/weston.log >/work/logs/weston.out 2>&1 &
sleep 2
export GREETD_SOCK="$XDG_RUNTIME_DIR/greetd.sock"
nohup python3 /work/dev/fake-greetd.py > /work/logs/greetd.log 2>&1 &
sleep 0.5

mkdir -p /root/.config/quickshell
ln -sfn /work/greeter /root/.config/quickshell/shani-greeter
ln -sfn /work/setup /root/.config/quickshell/shani-setup
export SHANI_SETUP_APPLY="python3 /work/bridge/first-account.py" SHANI_OSK_LAYOUT_TOOL=/work/bridge/osk-layout.py
export SHANI_GREETER_WALLPAPER=/work/assets/wallpaper.png

start_niri() {
    rm -f "$XDG_RUNTIME_DIR"/wayland-1 "$XDG_RUNTIME_DIR"/wayland-1.lock
    WAYLAND_DISPLAY=wayland-parent nohup niri -c "$KDL" > /work/logs/setup-niri.log 2>&1 &
    NIRI_PID=$!
}
start_niri
i=0
until pgrep -f '^qs -c shani-setup' >/dev/null && [ -S "$XDG_RUNTIME_DIR/wayland-1" ] || [ "$i" -ge 40 ]; do sleep 0.25; i=$((i + 1)); done
pgrep -f '^qs -c shani-setup' >/dev/null && result setup-starts-without-accounts PASS || result setup-starts-without-accounts FAIL "$(pgrep -af 'qs -c')"
export WAYLAND_DISPLAY=wayland-1
st() { timeout 5 qs -c shani-setup ipc call setup state 2>/dev/null; }
call() { qs -c shani-setup ipc call setup "$@" >/dev/null 2>&1; }
waitfor() {
    i=0; while [ "$i" -lt $(($2 * 4)) ]; do
        st | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if ($1) else 1)" 2>/dev/null && return 0
        sleep 0.25; i=$((i + 1))
    done; return 1
}
shot() { sleep "${2:-0.8}"; grim "/work/docs/shots/$1.png" 2>/dev/null || true; }

waitfor "d['locales'] > 0 and d['zones'] > 0 and d['locale'] != ''" 10 && result setup-reads-system PASS || result setup-reads-system FAIL "$(st)"
shot 80-setup-welcome 1.5
call next
waitfor "d['page'] == 'keyboard'" 3
call set keymap "us,in+marathi"
shot 81-setup-keyboard
call next
waitfor "d['page'] == 'network'" 3
shot 82-setup-network
call next
call set timezone Asia/Kolkata
shot 83-setup-time
call next
waitfor "d['page'] == 'account'" 3
call set fullname "Shani Tester"
waitfor "d['username'] == 'shani' and d['hostname'] == 'shani-shani'" 3 && result setup-suggests-names PASS || result setup-suggests-names FAIL "$(st)"
call set password shani
call set password2 nope
waitfor "'match' in d['problem']" 2 && result setup-checks-passwords PASS || result setup-checks-passwords FAIL "$(st)"
call next
sleep 0.5
getent passwd shani >/dev/null && result setup-waits-for-a-valid-form FAIL || result setup-waits-for-a-valid-form PASS
call set password2 shani
shot 84-setup-account 0.5
call next
# the wizard quits once the session is launched; niri then ends
i=0; while kill -0 "$NIRI_PID" 2>/dev/null && [ "$i" -lt 60 ]; do sleep 0.25; i=$((i + 1)); done

getent passwd shani | grep -q ':Shani Tester:/home/shani:/bin/bash$' && result setup-creates-account PASS || result setup-creates-account FAIL "$(getent passwd shani)"
id -nG shani | grep -qw wheel && result setup-account-is-admin PASS || result setup-account-is-admin FAIL "$(id -nG shani)"
grep -q '^shani:\$' /etc/shadow && result setup-sets-password PASS || result setup-sets-password FAIL
[ -d /home/shani ] && result setup-creates-home PASS || result setup-creates-home FAIL
LOG=/work/logs/greetd.log
python3 - "$LOG" <<'PY' && result setup-signs-in PASS || result setup-signs-in FAIL "$(cat $LOG)"
import json, sys
msgs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][1:]
types = [m["type"] for m in msgs]
ok = types[:2] == ["create_session", "post_auth_message_response"] and msgs[0].get("username") == "shani" \
     and msgs[1].get("response") == "shani" and types[-1] == "start_session" and msgs[-1]["cmd"] == ["niri-session"]
sys.exit(0 if ok else 1)
PY

# a second boot of the same machine: the login screen, and no second account
pkill -f fake-greetd.py; sleep 0.3
nohup python3 /work/dev/fake-greetd.py >> /work/logs/greetd2.log 2>&1 &
sleep 0.5
start_niri
i=0
until pgrep -f '^qs -c shani-greeter' >/dev/null || [ "$i" -ge 40 ]; do sleep 0.25; i=$((i + 1)); done
pgrep -f '^qs -c shani-greeter' >/dev/null && ! pgrep -f '^qs -c shani-setup' >/dev/null \
    && result login-screen-once-set-up PASS || result login-screen-once-set-up FAIL "$(pgrep -af 'qs -c')"
kill "$NIRI_PID" 2>/dev/null
out=$(echo '{"username": "intruder", "password": "x"}' | python3 /work/bridge/first-account.py)
echo "$out" | grep -q 'already has an account' && ! getent passwd intruder >/dev/null \
    && result helper-refuses-second-account PASS || result helper-refuses-second-account FAIL "$out"

pkill -f fake-greetd.py 2>/dev/null || true
[ "$fail" = 0 ]
