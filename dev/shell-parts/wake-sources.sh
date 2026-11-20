# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=wake-sources)
# ---- Settings > Power: what can wake this computer ----
# bridge/wakeup.py reads a stand-in /sys (SHANI_SYSFS=/tmp/fake-sys, dev/session.sh):
# a USB keyboard that may wake it, a hub and a card reader that are not listed.
# Its switch is pressed through AT-SPI; dev/fake-admin.sh records the request
# shani-admin.py would get (the real action: tests/test_wakeup.py, as root: admin-test).
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
S=/tmp/fake-sys; rm -rf "$S"; mkdir -p "$S/bus/usb/devices" "$S/class/net"
K="$S/devices/pci0000:00/0000:00:14.0/usb1/1-3"; mkdir -p "$K/power"
echo enabled > "$K/power/wakeup"; echo 046d > "$K/idVendor"; echo 00 > "$K/bDeviceClass"
echo "USB Keyboard" > "$K/product"; echo Logitech > "$K/manufacturer"
ln -s "$K" "$S/bus/usb/devices/1-3"
H="$S/devices/pci0000:00/0000:00:14.0/usb1"; mkdir -p "$H/power"; echo disabled > "$H/power/wakeup"
echo 1d6b > "$H/idVendor"; echo 09 > "$H/bDeviceClass"; echo "xHCI Host Controller" > "$H/product"
ln -s "$H" "$S/bus/usb/devices/usb1"
rm -f /tmp/admin-log
if [ -f "$A11Y" ]; then
    ipc settingsCategory power; sleep 1.5
    # the whole tree, not `find`: the section can be below the fold (find is on-screen only)
    i=0; until timeout 20 python3 "$A11Y" tree --max-depth 60 2>/dev/null | grep -qF "check box 'Logitech USB Keyboard'" || [ $i -ge 10 ]; do sleep 0.5; i=$((i+1)); done
    T=$(timeout 20 python3 "$A11Y" tree --max-depth 60 2>/dev/null)
    echo "$T" | grep -qF "check box 'Logitech USB Keyboard'" \
        && result wake-sources-listed PASS || result wake-sources-listed FAIL "$(echo "$T" | grep -iE "keyboard|wake|lid" | head -4 | tr "\n" ";") lines=$(echo "$T" | wc -l)"
    echo "$T" | grep -qF "check box 'Logitech USB Keyboard'" && ! echo "$T" | grep -qF 'xHCI Host Controller' \
        && result wake-sources-no-hubs PASS || result wake-sources-no-hubs FAIL "$(echo "$T" | grep -iE 'xhci|wake this' | head -3)"
    shot wake-sources 0.3
    timeout 20 python3 "$A11Y" press "check box:^Logitech USB Keyboard$" >/dev/null 2>&1; sleep 1
    python3 -c 'import json,sys; c,_,r=open("/tmp/admin-log").read().strip().splitlines()[-1].partition(" "); sys.exit(not (c=="wakeup" and json.loads(r)=={"path":sys.argv[1],"enabled":False}))' "$K" 2>/dev/null \
        && result wake-sources-switch-asks-admin PASS || result wake-sources-switch-asks-admin FAIL "$(cat /tmp/admin-log 2>&1 | tail -2)"
    ipc closeAll
else
    result wake-sources-listed SKIP "no AT-SPI client (shani-testbed beside this repo)"
fi
rm -rf "$S"
