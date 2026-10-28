#!/bin/sh
# The polkit agent, end to end. It needs what a plain container lacks — a
# logind session to register against — so this runs in a systemd-booted
# container (dev/polkit-run.sh), as a wheel user logged in with `login -f`
# (PAM + pam_systemd: a real session, a real user bus, real polkitd).
#   pkexec as that user -> polkitd -> our agent -> the dialog -> typed password
# Prints RESULT lines.
export XDG_SESSION_TYPE=wayland SHANI_SHELL_SETTINGS=/tmp/shani-settings-$USER.json
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
L=/work/logs
fail=0
result() { echo "RESULT $1 $2${3:+ ($3)}"; [ "$2" = PASS ] || fail=1; }
st() { qs -p /work/shani ipc call shani state 2>/dev/null; }
waitfor() {
    i=0
    while [ $i -lt $(( $2 * 4 )) ]; do
        st | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if ($1) else 1)" 2>/dev/null && return 0
        sleep 0.25; i=$((i+1))
    done
    return 1
}

[ -n "$XDG_SESSION_ID" ] && result logind-session PASS "$XDG_SESSION_ID" || result logind-session FAIL "no XDG_SESSION_ID"

weston --backend=headless-backend.so --shell=kiosk-shell.so --width=1920 --height=1080 \
    --socket=wayland-parent --idle-time=0 --no-config >$L/polkit-weston.log 2>&1 &
sleep 1.5
WAYLAND_DISPLAY=wayland-parent niri -c /work/dev/niri/session.kdl >$L/polkit-niri.log 2>&1 &
i=0; until [ -S "$XDG_RUNTIME_DIR/wayland-1" ] || [ $i -ge 40 ]; do sleep 0.25; i=$((i+1)); done
export WAYLAND_DISPLAY=wayland-1
qs -p /work/shani >$L/polkit-qs.log 2>&1 &

waitfor "d['polkitRegistered']" 10 && result polkit-agent-registers PASS || result polkit-agent-registers FAIL "$(grep -i polkit $L/polkit-qs.log | tail -2)"

pkexec --disable-internal-agent true >$L/pkexec-1.log 2>&1 &
PK=$!
waitfor "d['polkit']" 8 && result polkit-dialog-appears PASS || result polkit-dialog-appears FAIL
sleep 0.8; grim /work/docs/shots/29-polkit.png
wtype "not-the-password" -k Return
sleep 3
kill -0 $PK 2>/dev/null && waitfor "d['polkit']" 3 && result polkit-refuses-wrong-password PASS || result polkit-refuses-wrong-password FAIL
grim /work/docs/shots/30-polkit-wrong.png
wtype "polkit-test" -k Return
i=0; while kill -0 $PK 2>/dev/null && [ $i -lt 40 ]; do sleep 0.25; i=$((i+1)); done
wait $PK; rc=$?
[ $rc = 0 ] && result polkit-authorises-pkexec PASS || result polkit-authorises-pkexec FAIL "pkexec exit $rc: $(cat $L/pkexec-1.log)"
waitfor "not d['polkit']" 4 && result polkit-dialog-closes PASS || result polkit-dialog-closes FAIL
[ "$fail" = 0 ]
