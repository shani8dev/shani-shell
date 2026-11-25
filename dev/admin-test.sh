#!/bin/sh
# usage: sh dev/admin-test.sh <shani-desktop-niri dir>   (from the repo root)
# bridge/shani-admin.py for real, as pkexec would run it (root, PKEXEC_UID =
# the asking account), in a systemd-booted dev container: real useradd,
# userdel, gpasswd, chpasswd; greetd's autologin copy + drop-in with a
# daemon-reload systemd accepts; logind's drop-in, read back from logind.
set -e
. "$(dirname "$0")/systemd-box.sh"
DESK=$(cd "${1:?shani-desktop-niri dir}" && pwd)
box_up -v "$REPO":/work:ro -v "$DESK":/desk:ro
docker exec -i "$cid" sh -s <<'IN'
fail=0
# result: the helpers every harness shares (dev/harness.sh)
. /work/dev/harness.sh
install -Dm644 /desk/etc/greetd/shani-niri.toml /etc/greetd/shani-niri.toml
useradd -m -G wheel asha && echo asha:pw | chpasswd
A() { PKEXEC_UID=$(id -u asha) python3 /work/bridge/shani-admin.py "$@"; }

out=$(echo '{"username": "meera", "fullname": "Meera K", "password": "m-pw", "admin": false}' | A user-add)
getent passwd meera | grep -q ':Meera K:/home/meera:/bin/bash$' && [ -d /home/meera ] && ! id -nG meera | grep -qw wheel \
    && result add-standard-user PASS || result add-standard-user FAIL "$out"
out=$(echo '{"username": "meera", "admin": true}' | A user-admin)
id -nG meera | grep -qw wheel && result make-admin PASS || result make-admin FAIL "$out"
out=$(echo '{"username": "meera", "admin": false}' | A user-admin)
id -nG meera | grep -qw wheel && result unmake-admin FAIL "$out" || result unmake-admin PASS
old=$(getent shadow meera | cut -d: -f2)
out=$(echo '{"username": "meera", "password": "new-pw"}' | A user-password)
[ "$(getent shadow meera | cut -d: -f2)" != "$old" ] && result reset-password PASS || result reset-password FAIL "$out"
out=$(echo '{"username": "asha"}' | A user-remove); getent passwd asha >/dev/null && echo "$out" | grep -q 'your own' \
    && result cannot-remove-self PASS || result cannot-remove-self FAIL "$out"
out=$(echo '{"username": "root", "password": "x"}' | A user-password); echo "$out" | grep -q 'system account' \
    && result root-off-limits PASS || result root-off-limits FAIL "$out"

out=$(echo '{"username": "meera"}' | A autologin)
systemctl show -p ExecStart greetd.service | grep -q 'shani-niri-autologin.toml' && grep -q 'user = "meera"' /etc/greetd/shani-niri-autologin.toml \
    && result autologin-on PASS || result autologin-on FAIL "$out $(systemctl cat greetd.service 2>&1 | tail -3)"
out=$(echo '{"username": "meera", "deleteHome": true}' | A user-remove)
! getent passwd meera >/dev/null && [ ! -d /home/meera ] && result remove-with-files PASS || result remove-with-files FAIL "$out"
[ ! -e /etc/systemd/system/greetd.service.d/20-shani-autologin.conf ] && result removing-autologin-user-turns-it-off PASS || result removing-autologin-user-turns-it-off FAIL

out=$(echo '{"lid": "lock", "lidOnPower": "ignore", "powerKey": "suspend"}' | A power-keys)
sleep 1
p() { busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "$1"; }
[ "$(p HandleLidSwitch)" = 's "lock"' ] && [ "$(p HandleLidSwitchExternalPower)" = 's "ignore"' ] && [ "$(p HandlePowerKey)" = 's "suspend"' ] \
    && result power-keys-reach-logind PASS || result power-keys-reach-logind FAIL "$out $(p HandleLidSwitch) $(p HandlePowerKey)"

# ---- the guest account: no password, never an admin, its home new before and after each session ----
install -Dm755 /desk/usr/lib/shani-desktop-niri/guest-reset /usr/lib/shani-desktop-niri/guest-reset
install -Dm644 /desk/usr/lib/systemd/system/user-runtime-dir@.service.d/50-shani-guest.conf /usr/lib/systemd/system/user-runtime-dir@.service.d/50-shani-guest.conf
install -Dm644 /desk/usr/lib/systemd/logind.conf.d/50-shani-guest.conf /usr/lib/systemd/logind.conf.d/50-shani-guest.conf
systemctl daemon-reload
systemctl kill -s HUP systemd-logind   # logind reads its drop-ins at start and on a reload (the package's is there from boot)
out=$(echo '{"on": true}' | A guest)
getent passwd guest | grep -q ':Guest:/home/guest:/bin/bash$' && [ "$(passwd -S guest | awk '{print $2}')" = NP ] && ! id -nG guest | grep -qw wheel \
    && [ "$(cat /etc/shani/guest)" = guest ] && result guest-on-no-password-no-admin PASS || result guest-on-no-password-no-admin FAIL "$out $(passwd -S guest 2>&1)"
g=$(id -u guest)
touch /home/guest/left-by-the-last-lesson; echo 'a note' > /etc/skel/.from-skel
systemctl start "user-runtime-dir@$g.service"
[ ! -e /home/guest/left-by-the-last-lesson ] && [ -e /home/guest/.from-skel ] && [ "$(stat -c %U /home/guest/.from-skel)" = guest ] \
    && result guest-home-new-before-a-session PASS || result guest-home-new-before-a-session FAIL "$(ls -la /home/guest | tail -3)"
touch /home/guest/written-this-lesson
systemctl stop "user-runtime-dir@$g.service"
[ ! -e /home/guest/written-this-lesson ] && [ -d /home/guest ] && [ "$(stat -c %a /home/guest)" = 700 ] \
    && result guest-home-new-after-a-session PASS || result guest-home-new-after-a-session FAIL "$(ls -la /home/guest | tail -3)"
# anyone else's start and stop leaves their home alone
a=$(id -u asha); touch /home/asha/keep-me
systemctl start "user-runtime-dir@$a.service"; systemctl stop "user-runtime-dir@$a.service"
[ -e /home/asha/keep-me ] && result guest-reset-leaves-others-alone PASS || result guest-reset-leaves-others-alone FAIL
sleep 1
[ "$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager KillOnlyUsers)" = 'as 1 "guest"' ] \
    && result guest-programs-end-with-the-session PASS || result guest-programs-end-with-the-session FAIL "$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager KillOnlyUsers 2>&1)"
out=$(echo '{"on": false}' | A guest)
! getent passwd guest >/dev/null && [ ! -e /etc/shani/guest ] && [ ! -d /home/guest ] \
    && result guest-off-gone PASS || result guest-off-gone FAIL "$out"
exit $fail
IN
