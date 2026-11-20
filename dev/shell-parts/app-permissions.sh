# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=app-permissions)
# ---- Settings > App permissions (Flatseal parity) against a stand-in flatpak:
#      the app's sections read, a switch written as `flatpak override --user`,
#      a portal answer, a folder added read-only, Reset ----
F=/tmp/fake-fp; rm -rf $F; mkdir -p $F
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
had=$(command -v flatpak || true)
printf '#!/bin/sh\nFAKE_FP=%s exec python3 /work/dev/fake-flatpak.py "$@"\n' "$F" > /usr/local/bin/flatpak; chmod +x /usr/local/bin/flatpak
ipc settingsAt apps ""; sleep 1.5
waitfor "d['appPermApps'] == ['org.example.App', 'io.other.Tool']" 6 && result app-perms-listed PASS || result app-perms-listed FAIL "$(q "['appPermApps']")"
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "list item:^Example" >/dev/null 2>&1 || timeout 20 python3 "$A11Y" press "button:^Example" >/dev/null 2>&1
    waitfor "'pulseaudio' in d['appPermShown']" 6 && result app-perms-shown PASS || result app-perms-shown FAIL "$(q "['appPermShown']" | head -c 200)"
    shot app-permissions 0.3
    timeout 20 python3 "$A11Y" press "check box:^Network" >/dev/null 2>&1 || timeout 20 python3 "$A11Y" press "switch:^Network" >/dev/null 2>&1
    waitfor "'\"changed\": {\"shared\": [\"network\"]}' in d['appPermShown'] or ('network' not in json.loads(d['appPermShown'])['shared'])" 6 \
        && grep -q 'override --user --unshare=network org.example.App' $F/calls && result app-perms-switch-overrides PASS || result app-perms-switch-overrides FAIL "$(tail -2 $F/calls | tr '\n' ';')"
    timeout 20 python3 "$A11Y" press "radio button:^Not allowed" >/dev/null 2>&1
    waitfor "json.loads(d['appPermShown'])['portals'].get('notifications') == 'no'" 6 && result app-perms-portal PASS || result app-perms-portal FAIL "$(q "['appPermShown']" | head -c 300)"
    timeout 20 python3 "$A11Y" press "button:^Back to what the app asked for" >/dev/null 2>&1
    waitfor "'network' in json.loads(d['appPermShown'])['shared'] and json.loads(d['appPermShown'])['changed'] == {}" 6 && result app-perms-reset PASS || result app-perms-reset FAIL "$(q "['appPermShown']" | head -c 300)"
fi
rm -f /usr/local/bin/flatpak; rm -rf $F; ipc closeAll
