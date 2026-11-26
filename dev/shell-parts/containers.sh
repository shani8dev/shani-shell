# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=containers)
# ---- Containers, against the stand-ins (dev/fake-podman.py, dev/fake-machinectl.py):
#      listed, a toolbox made from a chip with home/GPU choices and its apps put in
#      the menu, a container started with picks and opened in a terminal, live logs,
#      pause/resume, a package installed, images searched and fetched, pods, volumes,
#      machines, machine images and disk-image boot, unused images pruned ----
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
rm -f /tmp/fake-podman/state.json /tmp/fake-podman/calls /tmp/fake-podman/exported /tmp/fake-podman/errors
SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani app containers >/dev/null 2>&1
waitfor "d['containersShown'] and 'box:' not in ' '.join(d['containersList']) and 'web:running' in d['containersList']" 8 && result containers-listed PASS || result containers-listed FAIL "$(q "['containersShown'], d['containersList']")"
shot app-containers 0.3
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "radio button:^Arch Linux$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "radio button:^Separate$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "radio button:^Use NVIDIA$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "button:^New toolbox$" >/dev/null 2>&1
    waitfor "d['containersDone'] == 'create arch:ok' and 'box:arch:exited' in d['containersList']" 15 && result containers-box-made PASS || result containers-box-made FAIL "$(q "['containersDone'], d['containersList']")"
    grep -q -- "--image docker.io/library/archlinux:latest" /tmp/fake-podman/calls || result containers-box-image FAIL "$(cat /tmp/fake-podman/calls)"
    grep -q -- "--nvidia" /tmp/fake-podman/calls && grep -q -- "--home " /tmp/fake-podman/calls && result containers-box-options PASS || result containers-box-options FAIL "$(cat /tmp/fake-podman/calls)"
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
    timeout 20 python3 "$A11Y" press "button:^Click again: remove unused images$" >/dev/null 2>&1
    waitfor "'docker.io/library/old:1' not in d['containersImages'] and len(d['containersImages']) == 2" 8 && result containers-prune PASS || result containers-prune FAIL "$(q "['containersImages']")"

    # toolbox details and a copy, with the choices made above recorded
    timeout 20 python3 "$A11Y" press "radio button:^Toolboxes$" >/dev/null 2>&1
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^Details$" >/dev/null 2>&1
    waitfor "'Arch Linux' in d['containersDetails']" 8 && result containers-box-details PASS || result containers-box-details FAIL "$(q "['containersDetails']")"
    timeout 20 python3 "$A11Y" press "button:^Make a copy$" >/dev/null 2>&1
    waitfor "d['containersDone'].startswith('copy arch') and any('arch-copy:exited' in x for x in d['containersList'])" 15 && result containers-box-clone PASS || result containers-box-clone FAIL "$(q "['containersDone'], d['containersList']")"

    # a container from picks, a terminal into it, live logs, pause and resume
    timeout 20 python3 "$A11Y" press "radio button:^Containers$" >/dev/null 2>&1
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^New container$" >/dev/null 2>&1
    shot app-containers-new 0.3
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^Start container$" >/dev/null 2>&1
    waitfor "d['containersStarted'] == 'app' and 'app:running' in d['containersList']" 10 && grep -q -- "podman run -d --name app" /tmp/fake-podman/calls && result containers-run PASS || result containers-run FAIL "$(q "['containersStarted'], d['containersList']") $(grep run /tmp/fake-podman/calls | tail -2)"
    timeout 20 python3 "$A11Y" press "button:^Open a shell$" >/dev/null 2>&1
    waitfor "'exec -it app' in d['containersTerminal']" 8 && result containers-shell PASS || result containers-shell FAIL "$(q "['containersTerminal']")"
    timeout 20 python3 "$A11Y" press "button:^More$" >/dev/null 2>&1
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^CPU and memory$" >/dev/null 2>&1
    waitfor "'12.5%' in d['containersStats']" 8 && result containers-stats PASS || result containers-stats FAIL "$(q "['containersStats']")"
    timeout 20 python3 "$A11Y" press "button:^Read live logs$" >/dev/null 2>&1
    waitfor "'follow one' in d['containersFollow']" 8 && result containers-follow PASS || result containers-follow FAIL "$(q "['containersFollow']")"
    timeout 20 python3 "$A11Y" press "button:^Pause$" >/dev/null 2>&1
    waitfor "'app:paused' in d['containersList']" 8 && result containers-pause PASS || result containers-pause FAIL "$(q "['containersList']")"
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^Resume$" >/dev/null 2>&1
    waitfor "'app:running' in d['containersList']" 8 && result containers-resume PASS || result containers-resume FAIL "$(q "['containersList']")"

    # registry search, fetch, pods and volumes
    timeout 20 python3 "$A11Y" press "radio button:^Images$" >/dev/null 2>&1
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^Search$" >/dev/null 2>&1
    waitfor "len(d['containersSearch']) >= 2" 8 && result containers-search PASS || result containers-search FAIL "$(q "['containersSearch']")"
    timeout 20 python3 "$A11Y" press "button:^Fetch$" >/dev/null 2>&1
    waitfor "d['containersDone'].startswith('pull ')" 8 && grep -q -- "podman pull " /tmp/fake-podman/calls && result containers-pull PASS || result containers-pull FAIL "$(q "['containersDone']")"
    timeout 20 python3 "$A11Y" press "radio button:^Pods$" >/dev/null 2>&1
    shot app-containers-pods 0.3
    waitfor "any('webpod' in x for x in d['containersPods'])" 8 && result containers-pods-listed PASS || result containers-pods-listed FAIL "$(q "['containersPods']")"
    timeout 20 python3 "$A11Y" press "button:^Stop$" >/dev/null 2>&1
    waitfor "'webpod:exited' in d['containersPods']" 8 && grep -q -- "pod stop webpod" /tmp/fake-podman/calls && result containers-pod-stop PASS || result containers-pod-stop FAIL "$(q "['containersPods']")"
    timeout 20 python3 "$A11Y" press "radio button:^Volumes$" >/dev/null 2>&1
    waitfor "'site' in d['containersVolumes']" 8 && result containers-volumes-listed PASS || result containers-volumes-listed FAIL "$(q "['containersVolumes']")"
    timeout 20 python3 "$A11Y" press "radio button:^cache$" >/dev/null 2>&1
    sleep 0.3
    timeout 20 python3 "$A11Y" press "button:^Create volume$" >/dev/null 2>&1
    waitfor "'cache' in d['containersVolumes']" 8 && result containers-volume-create PASS || result containers-volume-create FAIL "$(q "['containersVolumes']")"

    # machines, machine images and the disk-image boot button
    timeout 20 python3 "$A11Y" press "radio button:^Machines$" >/dev/null 2>&1
    shot app-containers-machines 0.4
    sleep 0.4
    waitfor "any('archlinux' in x for x in d['containersMachines'])" 8 && result containers-machines-listed PASS || result containers-machines-listed FAIL "$(q "['containersMachines']")"
    timeout 20 python3 "$A11Y" press "button:^Open a shell$" >/dev/null 2>&1
    waitfor "'machinectl shell archlinux' in d['containersTerminal']" 8 && result containers-machine-shell PASS || result containers-machine-shell FAIL "$(q "['containersTerminal']")"
    timeout 20 python3 "$A11Y" press "radio button:^Machine images$" >/dev/null 2>&1
    shot app-containers-machine-images 0.4
    sleep 0.4
    waitfor "any('archlinux' in x for x in d['containersMachineImages'])" 8 && result containers-machine-images-listed PASS || result containers-machine-images-listed FAIL "$(q "['containersMachineImages']")"
    timeout 20 python3 "$A11Y" press "button:^Make a copy$" >/dev/null 2>&1
    waitfor "'archlinux-copy' in d['containersMachineImages']" 8 && grep -q -- "machinectl clone archlinux archlinux-copy" /tmp/fake-podman/calls && result containers-image-clone PASS || result containers-image-clone FAIL "$(q "['containersMachineImages']")"
    timeout 20 python3 "$A11Y" press "button:^Fetch machine image$" >/dev/null 2>&1
    waitfor "d['containersDone'].startswith('fetch ')" 12 && grep -q -- "importctl pull-tar" /tmp/fake-podman/calls && result containers-image-pull PASS || { result containers-image-pull FAIL "$(q "['containersDone']")"; echo "  machine fetch controls:"; timeout 20 python3 "$A11Y" actionable 2>/dev/null | grep -i -E "fetch|image" | head -12 || true; tail -5 /tmp/fake-podman/calls 2>/dev/null || true; }
    timeout 20 python3 "$A11Y" press "radio button:^Boot a disk image$" >/dev/null 2>&1
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^Pick a disk image$" >/dev/null 2>&1 && sleep 0.5 && wtype -k Escape && result containers-vmspawn-offered PASS || result containers-vmspawn-offered FAIL
    timeout 20 python3 "$A11Y" press "radio button:^Toolboxes$" >/dev/null 2>&1
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^Install a package file$" >/dev/null 2>&1 && sleep 0.5 && wtype -k Escape && result containers-install-offered PASS || result containers-install-offered FAIL
fi
[ -s /tmp/fake-podman/errors ] && { echo "  the stand-in failed:"; cat /tmp/fake-podman/errors; }
ipc closeAll
