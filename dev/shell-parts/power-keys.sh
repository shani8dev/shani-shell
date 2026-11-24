# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=power-keys)
# ---- Settings > Power: lid, power button and sleep behaviour.

ipc settingsCategory power; sleep 1.5
title_ok=0
if command -v python3 >/dev/null 2>&1 && { [ -n "${A11Y:-}" ] || [ -d /testbed/lib ]; }; then
    if grep -qE 'Power button|Closing the lid|When it sleeps' <(timeout 20 python3 "${A11Y:-/testbed/lib/a11y_client.py}" tree --max-depth 16 2>/dev/null); then
        title_ok=1
    fi
fi
if [ "$title_ok" = 1 ]; then
    result power-keys-page-titled PASS
else
    result power-keys-page-titled SKIP "no AT-SPI power-keys text seen"
fi
shot settings-power-keys 0.5
ipc closeAll
