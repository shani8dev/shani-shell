# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=containers)
# ---- Containers (Pods' and BoxBuddy's jobs), against the stand-in podman and
#      distrobox (dev/fake-podman.py): listed, a container stopped by its button, a
#      toolbox made from a distro chip, its apps listed and one put in the menu,
#      opened in the terminal, unused images pruned ----
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
rm -f /tmp/fake-podman/state.json /tmp/fake-podman/calls /tmp/fake-podman/exported /tmp/fake-podman/errors
SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani app containers >/dev/null 2>&1
waitfor "d['containersShown'] and 'box:' not in ' '.join(d['containersList']) and 'web:running' in d['containersList']" 8 && result containers-listed PASS || result containers-listed FAIL "$(q "['containersShown'], d['containersList']")"
shot app-containers 0.3
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "radio button:^Arch Linux$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "button:^New toolbox$" >/dev/null 2>&1
    waitfor "d['containersDone'] == 'create arch:ok' and 'box:arch:exited' in d['containersList']" 15 && result containers-box-made PASS || result containers-box-made FAIL "$(q "['containersDone'], d['containersList']")"
    grep -q -- "--image docker.io/library/archlinux:latest" /tmp/fake-podman/calls || result containers-box-image FAIL "$(cat /tmp/fake-podman/calls)"
    timeout 20 python3 "$A11Y" press "button:^Its apps, for your menu$" >/dev/null 2>&1
    waitfor "'firefox' in d['containersApps']" 8 && result containers-box-apps PASS || result containers-box-apps FAIL "$(q "['containersApps']")"
    timeout 20 python3 "$A11Y" press "button:^Add to menu$" >/dev/null 2>&1
    waitfor "d['containersExported'] != ''" 8 && grep -q "firefox" /tmp/fake-podman/exported 2>/dev/null && result containers-box-export PASS || result containers-box-export FAIL "$(q "['containersExported']") $(cat /tmp/fake-podman/exported 2>&1)"
    timeout 20 python3 "$A11Y" press "button:^Open$" >/dev/null 2>&1
    waitfor "d['containersEntered'] == 'arch'" 6 && result containers-box-open PASS || result containers-box-open FAIL "$(q "['containersEntered']")"
    timeout 20 python3 "$A11Y" press "radio button:^Containers$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "button:^Stop$" >/dev/null 2>&1
    waitfor "'web:exited' in d['containersList']" 8 && result containers-stop PASS || result containers-stop FAIL "$(q "['containersList']")"
    timeout 20 python3 "$A11Y" press "radio button:^Images$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "button:^Remove unused$" >/dev/null 2>&1
    waitfor "'docker.io/library/old:1' not in d['containersImages'] and len(d['containersImages']) == 2" 8 && result containers-prune PASS || result containers-prune FAIL "$(q "['containersImages']")"
fi
[ -s /tmp/fake-podman/errors ] && { echo "  the stand-in failed:"; cat /tmp/fake-podman/errors; }
ipc closeAll
