# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=lights)
# ---- Settings > Controllers: coloured lights (the kernel's multicolour LEDs) ----
# bridge/lighting.py reads the stand-in /sys/class/leds (SHANI_LEDS_DIR=/tmp/fake-leds,
# dev/session.sh): a handheld's stick rings, channels in blue-green-red order.
# A colour swatch is pressed through AT-SPI; dev/fake-admin.sh records the request
# (the real action, writing the channels in the light's own order: tests/test_lighting.py).
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
R="/tmp/fake-leds/go_s:rgb:joystick_rings"; rm -rf "$R"; mkdir -p "$R"
echo "blue green red" > "$R/multi_index"; echo "100 0 50" > "$R/multi_intensity"
echo 100 > "$R/max_brightness"; echo 50 > "$R/brightness"
rm -f /tmp/admin-log
if [ -f "$A11Y" ]; then
    ipc settingsAt input in-games; sleep 1.5
    i=0; until timeout 20 python3 "$A11Y" tree --max-depth 60 2>/dev/null | grep -qF "Stick lights: Orange" || [ $i -ge 10 ]; do sleep 0.5; i=$((i+1)); done
    timeout 20 python3 "$A11Y" tree --max-depth 60 2>/dev/null | grep -qF "Stick lights: Orange" \
        && result lights-listed PASS || result lights-listed FAIL "$(python3 /work/bridge/lighting.py list 2>&1 | head -c 300)"
    shot lights 0.3
    timeout 20 python3 "$A11Y" press "radio button:^Stick lights: Orange$" >/dev/null 2>&1; sleep 1
    python3 -c 'import json,sys; c,_,r=open("/tmp/admin-log").read().strip().splitlines()[-1].partition(" "); sys.exit(not (c=="lighting" and json.loads(r)=={"led":"go_s:rgb:joystick_rings","color":"#ff9500","level":50}))' 2>/dev/null \
        && result lights-colour-asks-admin PASS || result lights-colour-asks-admin FAIL "$(tail -2 /tmp/admin-log 2>&1)"
    ipc closeAll
else
    result lights-listed SKIP "no AT-SPI client (shani-testbed beside this repo)"
fi
rm -rf "$R"
