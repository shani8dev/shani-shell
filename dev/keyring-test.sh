#!/bin/sh
# usage: keyring-test.sh   (inside the systemd-booted dev container: `sh dev/check.sh keyring`)
# The keyring a sign-in unlocks: shani-desktop-niri's greeter stack
# (/desk/etc/pam.d/shani-greetd) through the real libpam (dev/pam-session.py), in a
# container whose PID 1 is systemd - so pam_systemd makes a real logind session,
# alice's own systemd starts oo7-daemon (default.target.wants), and pam_oo7 hands
# it the password. A secret stored then read back WITHOUT any prompt proves the
# keyring was unlocked by the sign-in; a second sign-in (the user's systemd and
# the daemon gone in between, as after a restart) must unlock the same keyring.
fail=0
result() { echo "RESULT $1 $2${3:+ ($3)}"; if [ "$2" = FAIL ]; then fail=1; fi; }
pacman -Sy --noconfirm --needed oo7 >/dev/null 2>&1 || { result keyring-oo7-installed FAIL "pacman -S oo7"; exit 1; }
cp /desk/etc/pam.d/shani-greetd /etc/pam.d/shani-greetd
mkdir -p /usr/lib/shani-desktop-niri /usr/lib/systemd/user/default.target.wants
cp /desk/usr/lib/shani-desktop-niri/* /usr/lib/shani-desktop-niri/
cp -P /desk/usr/lib/systemd/user/default.target.wants/oo7-daemon.service /usr/lib/systemd/user/default.target.wants/
# THIS CONTAINER ONLY: a user's systemd in Docker cannot set up oo7-daemon's own
# sandbox (PrivateUsers= and friends: exit 218/CAPABILITIES), so it is relaxed
# here. The unit as shipped is checked on a booted slot (shani-testbed), not here.
mkdir -p /etc/systemd/user/oo7-daemon.service.d
printf '[Service]\nPrivateUsers=no\nPrivateDevices=no\nPrivateNetwork=no\nPrivateTmp=no\nProtectSystem=no\nProtectKernelTunables=no\nProtectKernelModules=no\nProtectControlGroups=no\nProtectClock=no\nMemoryDenyWriteExecute=no\nNoNewPrivileges=no\n' \
    > /etc/systemd/user/oo7-daemon.service.d/container-only.conf
id alice >/dev/null 2>&1 || useradd -m alice
echo "alice:keyring-pass" | chpasswd
U=$(id -u alice)
as_alice() { runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/$U DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$U/bus "$@"; }

# signin NAME: open a session through the greeter's stack; the session stays open
# until signout. Leaves the driver's output in /tmp/pam-NAME.
signin() {
    rm -f /tmp/pam-fifo; mkfifo /tmp/pam-fifo
    python3 /work/dev/pam-session.py shani-greetd alice keyring-pass < /tmp/pam-fifo > "/tmp/pam-$1" 2>&1 &
    PAM_PID=$!
    exec 3>/tmp/pam-fifo
    i=0; until grep -qE '^(open|fail)' "/tmp/pam-$1" 2>/dev/null || [ $i -ge 40 ]; do sleep 0.25; i=$((i+1)); done
    i=0; until as_alice systemctl --user is-active -q oo7-daemon.service 2>/dev/null || [ $i -ge 40 ]; do sleep 0.25; i=$((i+1)); done
    sleep 1   # pam_oo7's session step hands the password over on the daemon's socket
}
signout() {
    echo close >&3; exec 3>&-; wait "$PAM_PID" 2>/dev/null
    # the last session gone, alice's systemd is stopped - and oo7-daemon with it, its
    # keyring locked - as a restart would (logind waits UserStopDelaySec, 10 s, for that)
    systemctl stop "user@$U.service" 2>/dev/null
    i=0; while [ -d "/run/user/$U" ] && [ $i -lt 60 ]; do sleep 0.25; i=$((i+1)); done
}
# a read that cannot answer a prompt: a locked keyring would ask for its password
lookup() { printf '' | timeout 10 sh -c "$(printf 'XDG_RUNTIME_DIR=/run/user/%s DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%s/bus runuser -u alice -- oo7-cli lookup --secret-only app=shani-keyring-test' "$U" "$U")" 2>&1; }

# ---- the first sign-in: the keyring is made and unlocked with the password ----
signin first
grep -qx open /tmp/pam-first && result keyring-signin-opens-session PASS || result keyring-signin-opens-session FAIL "$(cat /tmp/pam-first)"
as_alice systemctl --user is-active -q oo7-daemon.service && result keyring-daemon-started PASS \
    || result keyring-daemon-started FAIL "$(journalctl --no-pager -q _UID=$U -t oo7-daemon -t systemd -n 25 2>&1 | tr '\n' '|' | tail -c 1500)"
printf 'keyring-secret' | timeout 10 runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/$U DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$U/bus \
    oo7-cli store "shani keyring test" app=shani-keyring-test >/dev/null 2>&1
got=$(lookup)
[ "$got" = keyring-secret ] && result keyring-unlocked-by-signin PASS || result keyring-unlocked-by-signin FAIL "got: $got"
as_alice systemctl --user show -p MainPID --value oo7-daemon.service > /tmp/oo7-pid-first 2>/dev/null
ls /home/alice/.local/share/keyrings/v1/*.keyring >/dev/null 2>&1 && result keyring-file-written PASS \
    || result keyring-file-written FAIL "$(ls -R /home/alice/.local/share/keyrings 2>&1 | head -5)"
signout
[ ! -d "/run/user/$U" ] && result keyring-session-ended PASS || result keyring-session-ended FAIL "/run/user/$U still there"

# ---- a second sign-in, the daemon started afresh: the same keyring, unlocked again ----
pid1=$(cat /tmp/oo7-pid-first 2>/dev/null)
signin second
pid2=$(as_alice systemctl --user show -p MainPID --value oo7-daemon.service 2>/dev/null)
[ -n "$pid2" ] && [ "$pid2" != 0 ] && [ "$pid2" != "$pid1" ] && result keyring-daemon-fresh PASS || result keyring-daemon-fresh FAIL "first $pid1, second $pid2"
got=$(lookup)
[ "$got" = keyring-secret ] && result keyring-unlocked-again PASS || result keyring-unlocked-again FAIL "got: $got"
signout
exit $fail
