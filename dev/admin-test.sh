#!/bin/sh
# usage: sh dev/admin-test.sh <shani-desktop-niri dir>   (from the repo root)
# bridge/shani-admin.py for real, as pkexec would run it (root, PKEXEC_UID =
# the asking account), in a systemd-booted dev container: real useradd,
# userdel, gpasswd, chpasswd; greetd's autologin copy + drop-in with a
# daemon-reload systemd accepts; logind's drop-in, read back from logind.
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
DESK=$(cd "${1:?shani-desktop-niri dir}" && pwd)
cid=$(docker run -d --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      --tmpfs /run --tmpfs /run/lock -v "$REPO":/work:ro -v "$DESK":/desk:ro shani-shell-dev /usr/lib/systemd/systemd)
trap 'docker rm -f "$cid" >/dev/null' EXIT
i=0; until docker exec "$cid" systemctl is-system-running 2>/dev/null | grep -qE "running|degraded" || [ $i -ge 60 ]; do sleep 1; i=$((i+1)); done
docker exec -i "$cid" sh -s <<'IN'
fail=0
result() { echo "RESULT $1 $2 ${3:+($3)}"; [ "$2" = FAIL ] && fail=1; true; }
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
exit $fail
IN
