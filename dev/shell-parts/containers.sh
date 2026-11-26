# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=containers)
# ---- Containers, against the stand-ins (dev/fake-podman.py, dev/fake-machinectl.py):
#      listed, a toolbox made from a chip with home/GPU choices and its apps put in
#      the menu, a container started with picks and opened in a terminal, live logs,
#      pause/resume, a package installed, images searched and fetched, pods, volumes,
#      machines, machine images and disk-image boot, unused images pruned ----
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
rm -f /tmp/fake-podman/state.json /tmp/fake-podman/calls /tmp/fake-podman/exported /tmp/fake-podman/errors
rm -f /tmp/fake-lxc/*.json /tmp/fake-lxc/calls /tmp/fake-lxc/errors /tmp/fake-lxc/uninitialised
rm -f /tmp/fake-apptainer/*.json /tmp/fake-apptainer/calls /tmp/fake-apptainer/errors
rm -f /tmp/fake-virsh/*.json /tmp/fake-virsh/calls /tmp/fake-virsh/errors /tmp/fake-virsh/undefined
rm -f /tmp/fake-waydroid/*.json /tmp/fake-waydroid/calls /tmp/fake-waydroid/errors /tmp/fake-waydroid/notinitialised
rm -f /tmp/fake-compose/*.json /tmp/fake-compose/calls /tmp/fake-compose/errors /tmp/fake-compose/compose
mkdir -p /tmp/container-build
printf 'FROM alpine\nCOPY . /app\n' > /tmp/container-build/Dockerfile
SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani app containers >/dev/null 2>&1
waitfor "d['containersShown'] and 'box:' not in ' '.join(d['containersList']) and 'web:running' in d['containersList']" 8 && result containers-listed PASS || result containers-listed FAIL "$(q "['containersShown'], d['containersList']")"
shot app-containers 0.3
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "radio button:^Arch Linux$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "radio button:^Separate$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "check box:^Use the graphics card$" >/dev/null 2>&1
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
    sleep 1.5
    timeout 20 python3 "$A11Y" press "button:^Stop$" >/dev/null 2>&1
    waitfor "'web:exited' in d['containersList']" 8 && result containers-stop PASS || { result containers-stop FAIL "$(q "['containersList']")"; echo "  stop controls:"; timeout 20 python3 "$A11Y" actionable 2>/dev/null | grep -i "stop" | head -8 || true; }
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

    # the running app container's files: list, enter a folder, up, back, copy out
    timeout 20 python3 "$A11Y" press "button:^Browse its files$" >/dev/null 2>&1
    sleep 1.0
    shot app-containers-files 0.4
    timeout 20 python3 "$A11Y" actionable 2>/dev/null | grep -q "Copy out notes.txt" \
        && result containers-files-listed PASS || result containers-files-listed FAIL "$(timeout 20 python3 "$A11Y" actionable 2>/dev/null | grep -i -E 'copy|browse|folder' | head -12)"
    timeout 20 python3 "$A11Y" press "button:^Enter folder docs$" >/dev/null 2>&1
    sleep 0.6
    grep -q -- "podman exec app ls -lA /docs" /tmp/fake-podman/calls \
        && result containers-files-enter PASS || result containers-files-enter FAIL "$(tail -5 /tmp/fake-podman/calls)"
    nup=$(grep -c -- "podman exec app ls -lA /$" /tmp/fake-podman/calls || true)
    timeout 20 python3 "$A11Y" press "button:^Up$" >/dev/null 2>&1
    sleep 0.6
    [ "$(grep -c -- "podman exec app ls -lA /$" /tmp/fake-podman/calls)" -gt "$nup" ] \
        && result containers-files-up PASS || result containers-files-up FAIL "$(tail -5 /tmp/fake-podman/calls)"
    nback=$(grep -c -- "podman exec app ls -lA /docs" /tmp/fake-podman/calls || true)
    timeout 20 python3 "$A11Y" press "button:^Back$" >/dev/null 2>&1
    sleep 0.6
    [ "$(grep -c -- "podman exec app ls -lA /docs" /tmp/fake-podman/calls)" -gt "$nback" ] \
        && result containers-files-back PASS || result containers-files-back FAIL "$(tail -5 /tmp/fake-podman/calls)"
    rm -f /tmp/notes.txt
    timeout 20 python3 "$A11Y" press "button:^Up$" >/dev/null 2>&1
    sleep 0.5
    timeout 20 python3 "$A11Y" press "button:^Copy out notes.txt$" >/dev/null 2>&1
    waitfor "d['pickerShown']" 6
    ipc filePickerGo /tmp
    ipc filePickerAccept
    sleep 0.8
    grep -q -- "podman cp app:/notes.txt /tmp/notes.txt" /tmp/fake-podman/calls \
        && result containers-file-copy PASS || result containers-file-copy FAIL "$(tail -5 /tmp/fake-podman/calls)"
    timeout 20 python3 "$A11Y" press "button:^Close the file list$" >/dev/null 2>&1

    # registry search, fetch, pods and volumes
    timeout 20 python3 "$A11Y" press "radio button:^Images$" >/dev/null 2>&1
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^Search$" >/dev/null 2>&1
    waitfor "len(d['containersSearch']) >= 2" 8 && result containers-search PASS || result containers-search FAIL "$(q "['containersSearch']")"
    timeout 20 python3 "$A11Y" press "button:^Fetch$" >/dev/null 2>&1
    waitfor "d['containersDone'].startswith('pull ')" 8 && grep -q -- "podman pull " /tmp/fake-podman/calls && result containers-pull PASS || result containers-pull FAIL "$(q "['containersDone']")"

    # build an image from a folder, then from a picked Dockerfile
    timeout 20 python3 "$A11Y" press "button:^Build from a file$" >/dev/null 2>&1
    shot app-containers-build 0.4
    sleep 0.3
    timeout 20 python3 "$A11Y" press "button:^Pick a folder$" >/dev/null 2>&1
    waitfor "d['pickerShown']" 6
    ipc filePickerGo /tmp/container-build
    ipc filePickerAccept
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^Build image$" >/dev/null 2>&1
    waitfor "d['containersDone'] == 'build my-app:latest:ok'" 15 && \
        grep -q -- "podman build -t my-app:latest /tmp/container-build" /tmp/fake-podman/calls \
        && result containers-build PASS || result containers-build FAIL "$(q "['containersDone']") $(grep build /tmp/fake-podman/calls | tail -3)"
    timeout 20 python3 "$A11Y" press "button:^Pick a Dockerfile$" >/dev/null 2>&1
    waitfor "d['pickerShown']" 6
    ipc filePickerSelect /tmp/container-build/Dockerfile
    ipc filePickerAccept
    sleep 0.4
    for _try in 1 2 3 4 5 6; do
        timeout 20 python3 "$A11Y" press "button:^Build image$" >/dev/null 2>&1
        sleep 0.5
        grep -q -- "podman build -t my-app:latest -f /tmp/container-build/Dockerfile /tmp/container-build" /tmp/fake-podman/calls && break
    done
    grep -q -- "podman build -t my-app:latest -f /tmp/container-build/Dockerfile /tmp/container-build" /tmp/fake-podman/calls \
        && result containers-build-file PASS || result containers-build-file FAIL "$(grep build /tmp/fake-podman/calls | tail -3)"
    shot app-containers-build-done 0.3

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
    timeout 20 python3 "$A11Y" press "radio button:^Machines & VMs$" >/dev/null 2>&1
    sleep 0.3
    timeout 20 python3 "$A11Y" press "radio button:^Machines$" >/dev/null 2>&1
    shot app-containers-machines 0.4
    sleep 0.4
    waitfor "any('archlinux' in x for x in d['containersMachines'])" 8 && result containers-machines-listed PASS || result containers-machines-listed FAIL "$(q "['containersMachines']")"
    timeout 20 python3 "$A11Y" press "button:^Open a shell$" >/dev/null 2>&1
    waitfor "'machinectl shell archlinux' in d['containersTerminal']" 8 && result containers-machine-shell PASS || result containers-machine-shell FAIL "$(q "['containersTerminal']")"
    timeout 20 python3 "$A11Y" press "radio button:^Machine images$" >/dev/null 2>&1
    shot app-containers-machine-images 0.4
    sleep 2.0
    waitfor "any('archlinux' in x for x in d['containersMachineImages'])" 8 && result containers-machine-images-listed PASS || result containers-machine-images-listed FAIL "$(q "['containersMachineImages']")"
    for _try in 1 2 3; do
        sleep 1.0
        timeout 20 python3 "$A11Y" press "button:^Make a copy$" >/dev/null 2>&1
        waitfor "'archlinux-copy' in d['containersMachineImages']" 5 && break
    done
    grep -q -- "machinectl clone archlinux archlinux-copy" /tmp/fake-podman/calls && result containers-image-clone PASS || result containers-image-clone FAIL "$(q "['containersMachineImages']")"
    timeout 20 python3 "$A11Y" press "button:^Fetch machine image$" >/dev/null 2>&1
    waitfor "d['containersDone'].startswith('fetch ')" 12 && grep -q -- "importctl pull-tar" /tmp/fake-podman/calls && result containers-image-pull PASS || { result containers-image-pull FAIL "$(q "['containersDone']")"; echo "  machine fetch controls:"; timeout 20 python3 "$A11Y" actionable 2>/dev/null | grep -i -E "fetch|image" | head -12 || true; tail -5 /tmp/fake-podman/calls 2>/dev/null || true; }
    timeout 20 python3 "$A11Y" press "radio button:^Boot a disk image$" >/dev/null 2>&1
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^Pick a disk image$" >/dev/null 2>&1 && sleep 0.5 && wtype -k Escape && result containers-vmspawn-offered PASS || result containers-vmspawn-offered FAIL
    timeout 20 python3 "$A11Y" press "radio button:^Toolboxes$" >/dev/null 2>&1
    sleep 0.4
    timeout 20 python3 "$A11Y" press "button:^Install a package file$" >/dev/null 2>&1 && sleep 0.5 && wtype -k Escape && result containers-install-offered PASS || result containers-install-offered FAIL

    # system containers through LXD
    timeout 20 python3 "$A11Y" press "radio button:^Machines & VMs$" >/dev/null 2>&1
    sleep 0.3
    timeout 20 python3 "$A11Y" press "radio button:^System containers$" >/dev/null 2>&1
    shot app-containers-lxd 0.4
    waitfor "any('web-lxd' in x for x in d['containersLxd'])" 8 && result containers-lxd-listed PASS || result containers-lxd-listed FAIL "$(q "['containersLxd']")"
    timeout 20 python3 "$A11Y" press "button:^Start system$" >/dev/null 2>&1
    waitfor "any('ubuntu:' in x for x in d['containersLxd'])" 8 && grep -q -- "lxc launch ubuntu:24.04 ubuntu" /tmp/fake-lxc/calls && result containers-lxd-launch PASS || result containers-lxd-launch FAIL "$(q "['containersLxd']")"
    timeout 20 python3 "$A11Y" press "button:^Open a shell$" >/dev/null 2>&1
    waitfor "'lxc exec' in d['containersTerminal']" 8 && result containers-lxd-shell PASS || result containers-lxd-shell FAIL "$(q "['containersTerminal']")"

    # HPC images, virtual machines, Android
    timeout 20 python3 "$A11Y" press "radio button:^Toolboxes$" >/dev/null 2>&1
    sleep 0.3
    timeout 20 python3 "$A11Y" press "radio button:^HPC images$" >/dev/null 2>&1
    shot app-containers-apptainer 0.4
    sleep 0.6
    waitfor "any('ubuntu_22.04.sif' in x for x in d['containersSif'])" 8 && result containers-sif-listed PASS || result containers-sif-listed FAIL "$(q "['containersSif']")"
    timeout 20 python3 "$A11Y" press "button:^Open a shell$" >/dev/null 2>&1
    waitfor "'apptainer shell' in d['containersTerminal']" 8 && result containers-sif-shell PASS || result containers-sif-shell FAIL "$(q "['containersTerminal']")"
    timeout 20 python3 "$A11Y" press "radio button:^Machines & VMs$" >/dev/null 2>&1
    sleep 0.3
    timeout 20 python3 "$A11Y" press "radio button:^Virtual machines$" >/dev/null 2>&1
    shot app-containers-vms 0.4
    sleep 1.0
    waitfor "any('dev-vm' in x for x in d['containersDomains'])" 8 && result containers-vms-listed PASS || result containers-vms-listed FAIL "$(q "['containersDomains']")"
    sleep 0.8
    timeout 20 python3 "$A11Y" press "button:^Console$" >/dev/null 2>&1
    waitfor "'virt-viewer' in d['containersTerminal']" 8 && result containers-vm-console PASS || { result containers-vm-console FAIL "$(q "['containersTerminal']")"; echo "  console controls:"; timeout 20 python3 "$A11Y" actionable 2>/dev/null | grep -i "console\|virt" | head -8 || true; }
    timeout 20 python3 "$A11Y" press "radio button:^Android$" >/dev/null 2>&1
    shot app-containers-android 0.4
    sleep 1.5
    waitfor "any('ready' in x for x in d['containersAndroid'])" 8 && result containers-android-status PASS || { result containers-android-status FAIL "$(q "['containersAndroid']")"; echo "  android controls:"; timeout 20 python3 "$A11Y" actionable 2>/dev/null | grep -i "android\|session" | head -8 || true; shot app-containers-android-debug 0.3; }
    timeout 20 python3 "$A11Y" press "button:^Start session$" >/dev/null 2>&1
    waitfor "any('RUNNING' in x for x in d['containersAndroid'])" 8 && result containers-android-start PASS || result containers-android-start FAIL "$(q "['containersAndroid']")"
    timeout 20 python3 "$A11Y" press "button:^Open Android apps$" >/dev/null 2>&1
    waitfor "'show-full-ui' in d['containersTerminal']" 8 && result containers-android-ui PASS || result containers-android-ui FAIL "$(q "['containersTerminal']")"

    # compose folder and service form are offered; their commands are bridge-tested
    timeout 20 python3 "$A11Y" press "radio button:^Containers$" >/dev/null 2>&1
    sleep 0.3
    timeout 20 python3 "$A11Y" press "radio button:^Compose$" >/dev/null 2>&1
    timeout 20 python3 "$A11Y" press "button:^Pick a compose file$" >/dev/null 2>&1 && sleep 0.5 && wtype -k Escape && result containers-compose-offered PASS || result containers-compose-offered FAIL
    timeout 20 python3 "$A11Y" press "radio button:^Services$" >/dev/null 2>&1
    shot app-containers-services 0.4
fi
[ -s /tmp/fake-podman/errors ] && { echo "  the stand-in failed:"; cat /tmp/fake-podman/errors; }
ipc closeAll
