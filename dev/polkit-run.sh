#!/bin/sh
# Host side of dev/polkit-test.sh: boot systemd in the dev image, make a wheel
# user, log it in for real, run the test, and tear down.
#   sh dev/polkit-run.sh            (from the repo root)
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$REPO/logs" "$REPO/docs/shots"
chmod 777 "$REPO/logs" "$REPO/docs/shots"
cid=$(docker run -d --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      --tmpfs /run --tmpfs /run/lock -v "$REPO":/work shani-shell-dev /usr/lib/systemd/systemd)
trap 'docker rm -f "$cid" >/dev/null' EXIT
i=0; until docker exec "$cid" systemctl is-system-running 2>/dev/null | grep -qE "running|degraded" || [ $i -ge 60 ]; do sleep 1; i=$((i+1)); done
docker exec "$cid" sh -c 'useradd -m -G wheel tester && echo tester:polkit-test | chpasswd'
# login(1) takes no command and reads its stdin itself; a login shell runs
# ~/.bash_profile, so the test goes there
docker exec "$cid" sh -c 'printf "sh /work/dev/polkit-test.sh\nexit\n" > /home/tester/.bash_profile'
docker exec "$cid" script -qec "login -f tester" /dev/null
