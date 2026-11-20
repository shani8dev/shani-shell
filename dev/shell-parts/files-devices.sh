# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-devices)
# ---- Files: drives, phones, cameras and servers in the sidebar (gio) ----
# dev/fake-gio.sh (SHANI_GIO) lists them in gio's own layout; a mounted one's
# files are /tmp/fake-gvfs/<name>, as gvfsd-fuse's local path.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
rm -f /tmp/gio-mounted /tmp/gio-log; rm -rf /tmp/fake-gvfs
ipc filesOpen "$HOME"
waitfor "'Pixel 8:closed' in d['filesDevices'] and 'STICK:closed' in d['filesDevices'] and 'Data:closed' in d['filesDevices']" 8 \
    && result files-devices-listed PASS || result files-devices-listed FAIL "$(q "['filesDevices']")"
shot files-devices 0.2
# a phone: a click mounts it and opens its files
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "button:^Pixel 8$" >/dev/null 2>&1
    waitfor "'Pixel 8:open' in d['filesDevices'] and d['filesPath'].startswith('/tmp/fake-gvfs/mtp')" 8 \
        && result files-device-click-mounts-and-opens PASS || result files-device-click-mounts-and-opens FAIL "$(q "['filesDevices'], d['filesPath'], d['filesError']")"
fi
# a URI handed to Files (what `gio open mtp://…` does with Files as the folder app) opens the same place
ipc filesOpen "afc://00008110/"
waitfor "d['filesPath'].startswith('/tmp/fake-gvfs/afc')" 8 && result files-opens-a-gvfs-uri PASS || result files-opens-a-gvfs-uri FAIL "$(q "['filesPath'], d['filesError']")"
# the USB stick: opened, then ejected - Files leaves it
/work/dev/fake-gio.sh mount -d /dev/sdb1; ipc filesOpen "/tmp/fake-gvfs/_dev_sdb1"; sleep 1
ipc filesEject STICK
waitfor "'STICK:closed' in d['filesDevices'] and not d['filesPath'].startswith('/tmp/fake-gvfs/_dev_sdb1')" 8 && grep -q '^mount -e ' /tmp/gio-log \
    && result files-device-eject PASS || result files-device-eject FAIL "$(q "['filesDevices'], d['filesPath']") $(tail -2 /tmp/gio-log | tr '\n' ';')"
# a server that asks who you are: the login fields appear; the right password opens it
ipc filesConnect "smb://nas/locked/" ann wrong
waitfor "d['filesConnectLogin'] and 'denied' in d['filesConnectError']" 8 && result files-connect-asks-login PASS || result files-connect-asks-login FAIL "$(q "['filesConnectError'], d['filesConnectLogin']")"
ipc filesConnect "smb://nas/locked/" ann pw
waitfor "d['filesPath'].startswith('/tmp/fake-gvfs/smb') and d['filesConnectError'] == ''" 8 && result files-connect-opens PASS || result files-connect-opens FAIL "$(q "['filesPath'], d['filesConnectError']")"
rm -f /tmp/gio-mounted; rm -rf /tmp/fake-gvfs; ipc closeAll
