# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-usb)
# ---- Files > Write to a USB drive / Format a USB drive (Impression's and GNOME
#      Disks' jobs) against a stand-in udisks2 (dev/session.sh): only the stick is
#      offered, the button waits for its name typed, then the bytes land ----
E=/tmp/files-usb; rm -rf $E; mkdir -p $E; rm -f /tmp/fake-udisks/calls /tmp/fake-udisks/sdb.img
head -c 3000000 /dev/urandom > $E/os.img; xz -k -T1 $E/os.img
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
ipc filesOpen "$E"; sleep 1
ipc filesUsb write "$E/os.img.xz"
waitfor "d['filesUsbDrives'] == ['SanDisk Cruzer Blade']" 6 && result files-usb-only-removable PASS || result files-usb-only-removable FAIL "$(q "['filesUsbDrives']")"
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "radio button:^SanDisk Cruzer Blade" >/dev/null 2>&1; sleep 0.5
    # not yet typed: Write does nothing
    timeout 20 python3 "$A11Y" press "button:^Write$" >/dev/null 2>&1; sleep 1
    [ ! -e /tmp/fake-udisks/sdb.img ] && result files-usb-asks-name-first PASS || result files-usb-asks-name-first FAIL "written without the name"
    timeout 20 python3 "$A11Y" press "text:^Type SanDisk Cruzer Blade" >/dev/null 2>&1
    sleep 0.3; wtype "SanDisk Cruzer Blade"; sleep 0.5
    shot files-usb-write 0.2
    timeout 20 python3 "$A11Y" press "button:^Write$" >/dev/null 2>&1
    waitfor "d['filesUsbResult'] != '' and not d['filesUsbBusy']" 20
    [ "$(md5sum < $E/os.img)" = "$(md5sum < /tmp/fake-udisks/sdb.img)" ] && result files-usb-write PASS "$(q "['filesUsbResult']")" || result files-usb-write FAIL "$(q "['filesUsbResult']"); $(ls -l /tmp/fake-udisks 2>&1 | tr '\n' ' ')"
    # format: exFAT with a name
    ipc filesUsb format ""
    waitfor "d['filesUsbDrives'] == ['SanDisk Cruzer Blade']" 6
    timeout 20 python3 "$A11Y" press "radio button:^SanDisk Cruzer Blade" >/dev/null 2>&1; sleep 0.5
    timeout 20 python3 "$A11Y" press "text:^Name" >/dev/null 2>&1
    sleep 0.3; wtype "PHOTOS"; sleep 0.3
    timeout 20 python3 "$A11Y" press "text:^Type SanDisk Cruzer Blade" >/dev/null 2>&1
    sleep 0.3; wtype "SanDisk Cruzer Blade"; sleep 0.5
    timeout 20 python3 "$A11Y" press "button:^Format$" >/dev/null 2>&1
    waitfor "'formatted' in d['filesUsbResult']" 10
    grep -q '"CreatePartitionAndFormat", \[1048576, 0, "0x07", "", "exfat", {}, {"label": "PHOTOS"}\]' /tmp/fake-udisks/calls \
        && result files-usb-format PASS || result files-usb-format FAIL "$(q "['filesUsbResult']"); $(cat /tmp/fake-udisks/calls 2>&1 | tr '\n' ' ')"
fi
# GNOME Disks' Create Disk Image: the stick's bytes into an image file in a folder
if [ -f "$A11Y" ]; then
    printf 'STICKBYTES%.0s' $(seq 1 1000) > /tmp/fake-udisks/sdb.disk; rm -f "$E"/*.img
    ipc filesUsb format ""; waitfor "d['filesUsbDrives'] == ['SanDisk Cruzer Blade']" 6
    timeout 20 python3 "$A11Y" press "radio button:^Back up to an image" >/dev/null 2>&1; sleep 0.3
    timeout 20 python3 "$A11Y" press "radio button:^SanDisk Cruzer Blade" >/dev/null 2>&1; sleep 0.3
    ipc filesUsbBackupTo "$E"
    waitfor "'copied into' in d['filesUsbResult']" 10
    img=$(ls "$E"/SanDisk*.img 2>/dev/null | head -1)
    [ -n "$img" ] && [ "$(md5sum < "$img")" = "$(md5sum < /tmp/fake-udisks/sdb.disk)" ] && result files-usb-backup PASS || result files-usb-backup FAIL "$(q "['filesUsbResult']") $(ls $E)"
    # a locked stick's password: the old one checked by udisks, then changed
    ipc filesUsb format ""; waitfor "d['filesUsbDrives'] == ['SanDisk Cruzer Blade']" 6
    timeout 20 python3 "$A11Y" press "radio button:^Change its password" >/dev/null 2>&1; sleep 0.3
    timeout 20 python3 "$A11Y" press "radio button:^SanDisk Cruzer Blade" >/dev/null 2>&1; sleep 0.3
    ipc filesUsbPassphrase "old-pw" "n3w"
    waitfor "'new password' in d['filesUsbResult']" 8 && grep -q ChangePassphrase /tmp/fake-udisks/calls && result files-usb-passphrase PASS || result files-usb-passphrase FAIL "$(q "['filesUsbResult']")"
    ipc closeAll
fi
# a disk image opened as a drive (read-only loop through udisks), then shown
mkdir -p /run/media/me/ARCH_202611; printf x > /run/media/me/ARCH_202611/boot.cfg
head -c 4096 /dev/zero > $E/arch.iso
ipc filesMountImage "$E/arch.iso"
waitfor "d['filesImageMounted'] == '/run/media/me/ARCH_202611' and d['filesPath'] == '/run/media/me/ARCH_202611'" 8 \
    && grep -q '"LoopSetup", \["arch.iso", {"read-only": true}\]' /tmp/fake-udisks/calls \
    && result files-image-mount PASS || result files-image-mount FAIL "$(q "['filesImageMounted'], d['filesPath'], d['filesError']"); $(grep Loop /tmp/fake-udisks/calls)"
# an encrypted stick (fake-gio's /dev/sdc1): opening it asks for its password; a
# wrong one says so, "pw" opens it
ipc filesOpen "$E"; sleep 0.8
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "button:^Locked stick$" >/dev/null 2>&1
    waitfor "d['filesUnlockFor'] == 'Locked stick'" 6 && result files-unlock-asks PASS || result files-unlock-asks FAIL "$(q "['filesUnlockFor'], d['filesError']")"
    shot files-unlock 0.2
    ipc filesUnlock wrong
    waitfor "d['filesUnlockError'] != ''" 6 && result files-unlock-wrong PASS || result files-unlock-wrong FAIL "$(q "['filesUnlockError']")"
    ipc filesUnlock pw
    waitfor "d['filesUnlockFor'] == '' and 'Locked stick:open' in d['filesDevices']" 6 && result files-unlock-opens PASS || result files-unlock-opens FAIL "$(q "['filesUnlockFor'], d['filesUnlockError'], d['filesDevices']")"
fi
ipc closeAll; rm -rf $E /run/media/me/ARCH_202611
: > /tmp/gio-mounted                                       # the unlocked stick closed again: no Eject left in Devices
# the network's servers (fake-gio's network://), offered in Connect to server
ipc filesServers
waitfor "'Office NAS' in d['filesServers'] and 'media' in d['filesServers']" 6 && result files-network-servers PASS || result files-network-servers FAIL "$(q "['filesServers']")"
# a folder shared on the network from its menu (net usershare, when Samba is here)
if command -v net >/dev/null && [ -d /var/lib/samba/usershare ]; then
    mkdir -p "$HOME/Shared Stuff"; ipc filesShare "$HOME/Shared Stuff" true
    waitfor "'$HOME/Shared Stuff' in d['filesShares']" 6 && result files-share-folder PASS || result files-share-folder FAIL "$(q "['filesShares'], d['filesError']")"
    ipc filesShare "$HOME/Shared Stuff" false; rmdir "$HOME/Shared Stuff"
fi
