# Sourced by the tests that need a real system (polkitd, logind, pkexec):
#   . "$(dirname "$0")/systemd-box.sh"; box_up [docker run args...]
# boots systemd in the dev image, waits until it is up, sets $cid and removes
# the container on exit. REPO is the shani-shell checkout.
REPO=$(cd "$(dirname "$0")/.." && pwd)
box_up() {
    cid=$(docker run -d --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
          --tmpfs /run --tmpfs /run/lock "$@" shani-shell-dev /usr/lib/systemd/systemd)
    trap 'docker rm -f "$cid" >/dev/null' EXIT
    i=0; until docker exec "$cid" systemctl is-system-running 2>/dev/null | grep -qE "running|degraded" || [ $i -ge 60 ]; do sleep 1; i=$((i+1)); done
}
