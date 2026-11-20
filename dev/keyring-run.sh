#!/bin/sh
# Host side of dev/keyring-test.sh: boot systemd in the dev image with
# shani-desktop-niri's files at /desk, run the test, tear down.
#   sh dev/keyring-run.sh <shani-desktop-niri dir>
set -e
DESK=${1:?usage: keyring-run.sh <shani-desktop-niri dir>}
. "$(dirname "$0")/systemd-box.sh"
box_up -v "$REPO":/work:ro -v "$DESK":/desk:ro
docker exec "$cid" sh /work/dev/keyring-test.sh
