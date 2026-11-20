# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=power-limit)
# ---- Settings > Power: a handheld's chip power limit ----
# bridge/powerlimit.py reads a stand-in /sys (SHANI_SYSFS=/tmp/fake-sys, dev/session.sh):
# ASUS firmware attributes, 7-30 W, now 17 W. A step is pressed through AT-SPI;
# dev/fake-admin.sh records the request (the real action: tests/test_powerlimit.py).
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
A=/tmp/fake-sys/class/firmware-attributes/asus-armoury/attributes
rm -rf /tmp/fake-sys
for a in ppt_pl1_spl ppt_pl2_sppt ppt_fppt; do
    mkdir -p "$A/$a"; echo 17 > "$A/$a/current_value"; echo 7 > "$A/$a/min_value"; echo 30 > "$A/$a/max_value"
done
rm -f /tmp/admin-log
if [ -f "$A11Y" ]; then
    ipc settingsCategory power; sleep 1.5
    i=0; until timeout 20 python3 "$A11Y" tree --max-depth 60 2>/dev/null | grep -qF "radio button '30 W'" || [ $i -ge 10 ]; do sleep 0.5; i=$((i+1)); done
    T=$(timeout 20 python3 "$A11Y" tree --max-depth 60 2>/dev/null)
    # 7..30 in five steps (7 13 19 24 30) plus the current 17
    for w in 7 13 17 19 24 30; do echo "$T" | grep -qF "radio button '$w W'" || miss="$miss $w"; done
    [ -z "$miss" ] && result power-limit-steps PASS || result power-limit-steps FAIL "missing:$miss"
    shot power-limit 0.3
    timeout 20 python3 "$A11Y" press "radio button:^24 W$" >/dev/null 2>&1; sleep 1
    python3 -c 'import json,sys; c,_,r=open("/tmp/admin-log").read().strip().splitlines()[-1].partition(" "); sys.exit(not (c=="power-limit" and json.loads(r)=={"watts":24}))' 2>/dev/null \
        && result power-limit-asks-admin PASS || result power-limit-asks-admin FAIL "$(tail -2 /tmp/admin-log 2>&1)"
    ipc closeAll
else
    result power-limit-steps SKIP "no AT-SPI client (shani-testbed beside this repo)"
fi
rm -rf /tmp/fake-sys
