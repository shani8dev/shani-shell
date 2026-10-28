#!/bin/sh
# usage: sh dev/setup-polkit-test.sh <shani-desktop-niri dir>   (from the repo root)
# The first-boot setup's privilege, against the real polkitd and pkexec in a
# systemd-booted dev container: the `greeter` user may run first-account.py
# through pkexec without a password while no account exists — and nothing
# else, nobody else, and not a second time.
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
# as the packages lay it out
install -Dm755 /work/bridge/first-account.py /usr/lib/shani-shell/first-account.py
install -Dm644 /desk/usr/share/polkit-1/rules.d/50-shani-setup.rules /usr/share/polkit-1/rules.d/50-shani-setup.rules
getent passwd greeter >/dev/null || useradd -r -M -s /usr/bin/nologin greeter
useradd -r -M -s /usr/bin/nologin stranger          # a system account, not a person's
systemctl restart polkit; sleep 1
req='{"username": "asha", "fullname": "Asha Patil", "password": "pw-1", "hostname": "asha-pc", "timezone": "Asia/Kolkata", "keymap": ["us", "in+marathi"], "keymapSwitch": "grp:win_space_toggle"}'

out=$(echo '{"username": "x1", "password": "p"}' | runuser -u stranger -- pkexec /usr/lib/shani-shell/first-account.py 2>&1)
getent passwd x1 >/dev/null && result others-cannot-run-it FAIL "$out" || result others-cannot-run-it PASS
out=$(runuser -u greeter -- pkexec /usr/bin/id -u 2>&1)
[ "$out" = 0 ] && result greeter-cannot-run-anything-else FAIL "$out" || result greeter-cannot-run-anything-else PASS
out=$(echo "$req" | runuser -u greeter -- pkexec /usr/lib/shani-shell/first-account.py 2>&1)
echo "$out" | grep -q '"ok": true' && getent passwd asha | grep -q ':Asha Patil:' && id -nG asha | grep -qw wheel \
    && result greeter-creates-first-account PASS "$out" || result greeter-creates-first-account FAIL "$out"
[ "$(timedatectl show -p Timezone --value)" = Asia/Kolkata ] && result first-account-sets-timezone PASS || result first-account-sets-timezone FAIL "$(timedatectl show -p Timezone --value)"
# docker bind-mounts /etc/hostname: hostnamed answers EBUSY (reported as a warning above)
if mountpoint -q /etc/hostname; then result first-account-sets-hostname SKIP "/etc/hostname is a container mount"
else [ "$(hostnamectl hostname)" = asha-pc ] && result first-account-sets-hostname PASS || result first-account-sets-hostname FAIL "$(hostnamectl hostname)"; fi
localectl status | grep -q 'X11 Layout: us,in' && result first-account-sets-keymap PASS || result first-account-sets-keymap FAIL "$(localectl status | tr '\n' ' ')"
out=$(echo '{"username": "mallory", "password": "p"}' | runuser -u greeter -- pkexec /usr/lib/shani-shell/first-account.py 2>&1)
echo "$out" | grep -q 'already has an account' && ! getent passwd mallory >/dev/null \
    && result no-second-account PASS || result no-second-account FAIL "$out"
exit $fail
IN
