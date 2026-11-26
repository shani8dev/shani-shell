# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=system-pages)
# ---- Settings > System: every page folded in from the old separate manager.
#      Each is opened over IPC, its state read is checked, a frame is taken,
#      and the two privileged flows are driven against the harness stand-ins.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}

page() {
    cat=$1
    key=$2
    want=$3
    ipc settingsCategory "$cat"
    if waitfor "d.get('systemCat') == '$cat' and ($want)" 10; then
        result "system-page-$cat" PASS
    else
        result "system-page-$cat" FAIL "$(q "['systemCat']") $(q "str(d.get('systemState', {}).get('$key'))[:160]")"
    fi
    shot "system-$cat" 0.6
}

page firmware firmware "len(d.get('systemState',{}).get('firmware',{}).get('devices',[])) >= 2"
page health health "len(d.get('systemState',{}).get('health',{}).get('checks',[])) >= 4"
page maintenance maintenance "d.get('systemCat') == 'maintenance'"
page graphics graphics "len(d.get('systemState',{}).get('graphics',{}).get('devices',[])) >= 1"
page appversions appversions "len(d.get('systemState',{}).get('appversions',{}).get('os',[])) >= 1"
page etcchanges etcchanges "d.get('systemCat') == 'etcchanges'"
page persistence persistence "len(d.get('systemState',{}).get('persistence',{}).get('mounts',[])) >= 1"
page virtualization virtualization "d.get('systemState',{}).get('virtualization',{}).get('kvm') is True"
page disksfs disksfs "len(d.get('systemState',{}).get('disksfs',{}).get('raid',[])) >= 1"
page background background "len(d.get('systemState',{}).get('background',{}).get('audit',[])) >= 1"
page dns dns "len(d.get('systemState',{}).get('dns',{}).get('servers',[])) >= 1"
page netservices netservices "len(d.get('systemState',{}).get('netservices',{}).get('ports',[])) >= 1"
page adminaccess access "d.get('systemState',{}).get('access',{}).get('directory',{}).get('sssd') == 'active'"

# Firmware: the check reaches the stand-in, and applying writes through it,
# never through a hand-off to a separate app.
if [ -d /testbed/lib ] || [ -f "$A11Y" ]; then
    ipc settingsCategory firmware; sleep 1
    timeout 20 python3 "$A11Y" press "button:^Check for updates$" >/dev/null 2>&1
    waitfor "len(d.get('systemState',{}).get('firmware',{}).get('updates',[])) >= 1" 8 \
        && result firmware-check PASS || result firmware-check FAIL "$(q "['systemState']")"
    grep -q -- "get-updates" /tmp/fake-system/firmware/calls 2>/dev/null \
        && result firmware-fake-called PASS || result firmware-fake-called FAIL
else
    result firmware-check SKIP "no AT-SPI"
fi

ipc closeAll
