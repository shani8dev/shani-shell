# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=network-zone)
# ---- a saved network marked as home: its firewall zone (NetworkManager's connection.zone) ----
# Every network is public (nothing unsolicited comes in) unless "Home network" is
# on for it; NetworkManager hands the zone to firewalld at once. dev/fake-nmcli.sh
# keeps the zone in /tmp/nm-zone. The switch is pressed through AT-SPI, as a person would.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}   # alone (shell=network-zone) this part runs before shell-test.sh sets it
if [ -f "$A11Y" ]; then
    ln -sf /work/dev/fake-nmcli.sh /usr/local/bin/nmcli; rm -f /tmp/nm-log /tmp/nm-zone
    ipc settingsCategory network; sleep 1.2
    timeout 20 python3 "$A11Y" press "check box:^Home network$" >/dev/null 2>&1; sleep 0.8
    [ "$(cat /tmp/nm-zone 2>/dev/null)" = home ] && result network-home-zone-set PASS || result network-home-zone-set FAIL "$(tail -3 /tmp/nm-log 2>&1 | tr '\n' ';')"
    shot network-home-zone 0.3
    timeout 20 python3 "$A11Y" press "check box:^Home network$" >/dev/null 2>&1; sleep 0.8
    [ -f /tmp/nm-zone ] && [ -z "$(cat /tmp/nm-zone)" ] && result network-home-zone-cleared PASS || result network-home-zone-cleared FAIL "$(tail -3 /tmp/nm-log 2>&1 | tr '\n' ';')"
    ipc closeAll; rm -f /usr/local/bin/nmcli /tmp/nm-zone
else
    result network-home-zone-set SKIP "no AT-SPI client (shani-testbed beside this repo)"
fi
