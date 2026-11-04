#!/bin/sh
# Host side of dev/polkit-test.sh: boot systemd in the dev image, make a wheel
# user, log it in for real, run the test, and tear down.
#   sh dev/polkit-run.sh            (from the repo root)
set -e
. "$(dirname "$0")/systemd-box.sh"
mkdir -p "$REPO/out/logs" "$REPO/out/shots"
chmod 777 "$REPO/out/logs" "$REPO/out/shots"
# the test runs as `tester`: last run's logs and shots (handed back to you by
# dev/check.sh) must stay writable for it
chmod a+w "$REPO"/out/logs/* "$REPO"/out/shots/* 2>/dev/null || true
box_up -v "$REPO":/work
docker exec "$cid" sh -c 'useradd -m -G wheel tester && echo tester:polkit-test | chpasswd'
# login(1) takes no command and reads its stdin itself; a login shell runs
# ~/.bash_profile, so the test goes there
docker exec "$cid" sh -c 'printf "sh /work/dev/polkit-test.sh\nexit\n" > /home/tester/.bash_profile'
docker exec "$cid" script -qec "login -f tester" /dev/null
