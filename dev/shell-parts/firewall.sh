# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=firewall)
# ---- Settings > Firewall: the zones, a zone's ports, a rich rule added and
#      taken off again, a zone of your own - every change through firewall-cmd
#      (dev/fake-firewall-cmd.sh), which records what it was asked in
#      /tmp/firewall-zones and /tmp/firewall-default, so the test reads the
#      change back the way a person would. ------------------------------------
FW=${SHANI_FIREWALL_CMD:-/work/dev/fake-firewall-cmd.sh}
Z=/tmp/firewall-zones
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
rm -f "$Z" /tmp/firewall-default /tmp/firewall-log

ipc settingsCategory firewall; sleep 1.6

# the page's read pass: firewalld is up, the default is public, public's ports
grep -q -- '--list-all-zones' /tmp/firewall-log \
    && result firewall-reads-zones PASS || result firewall-reads-zones FAIL "no read pass: $(tail -2 /tmp/firewall-log | tr '\n' ';')"
[ "$("$FW" --get-default-zone)" = public ] && result firewall-default-is-public PASS || result firewall-default-is-public FAIL "$("$FW" --get-default-zone)"

if [ -f "$A11Y" ]; then
    # the default zone: a click on the "home" chip (the first row of chips)
    timeout 20 python3 "$A11Y" press "radio button:^home$" >/dev/null 2>&1; sleep 1
    [ "$(cat /tmp/firewall-default 2>/dev/null)" = home ] && result firewall-default-zone-set PASS || result firewall-default-zone-set FAIL "$(tail -2 /tmp/firewall-log | tr '\n' ';')"
    timeout 20 python3 "$A11Y" press "radio button:^public$" >/dev/null 2>&1; sleep 1

    # a rich rule from a preset: firewalld's own wording, added at runtime
    timeout 20 python3 "$A11Y" press "radio button:^Reject ping$" >/dev/null 2>&1; sleep 1
    grep -q 'rule protocol value="icmp" reject' "$Z" \
        && result firewall-rich-rule-added PASS || result firewall-rich-rule-added FAIL "$(cut -d'|' -f6 "$Z" | tr '\n' ';')"

    # …typed by hand, which is the only way to reach a rule no preset covers
    timeout 20 python3 "$A11Y" press 'text:^rule service name="ssh" reject' >/dev/null 2>&1
    sleep 0.4; wtype 'rule family="ipv4" source address="10.0.0.0/8" service name="ssh" accept'; sleep 0.8
    timeout 20 python3 "$A11Y" press "button:^Add$" >/dev/null 2>&1; sleep 1.2
    grep -q 'source address="10.0.0.0/8"' "$Z" \
        && result firewall-rich-rule-typed PASS || result firewall-rich-rule-typed FAIL "$(cut -d'|' -f6 "$Z" | tr '\n' ';')"

    # …and taken off again, by the rule's own Remove (named after the rule, so
    # it is not confused with a port's or a service's Remove)
    timeout 20 python3 "$A11Y" press "button:^Remove rule family" >/dev/null 2>&1; sleep 1.2
    grep -q 'source address="10.0.0.0/8"' "$Z" \
        && result firewall-rich-rule-removed FAIL "$(cut -d'|' -f6 "$Z" | tr '\n' ';')" \
        || result firewall-rich-rule-removed PASS

    # a zone of your own, named, then deleted
    timeout 20 python3 "$A11Y" press 'text:^the name of a new zone' >/dev/null 2>&1
    sleep 0.4; wtype "lab"; sleep 0.6
    timeout 20 python3 "$A11Y" press "button:^New zone$" >/dev/null 2>&1; sleep 1.2
    "$FW" --get-zones | grep -qw lab && result firewall-zone-created PASS || result firewall-zone-created FAIL "$("$FW" --get-zones)"
    timeout 20 python3 "$A11Y" press "radio button:^Edit lab$" >/dev/null 2>&1; sleep 0.8
    timeout 20 python3 "$A11Y" press "button:^Delete the zone" >/dev/null 2>&1; sleep 1.2
    "$FW" --get-zones | grep -qw lab \
        && result firewall-zone-deleted FAIL "$("$FW" --get-zones)" || result firewall-zone-deleted PASS

    shot firewall-rules 0.3
fi
ipc closeAll; rm -f "$Z" /tmp/firewall-default /tmp/firewall-log