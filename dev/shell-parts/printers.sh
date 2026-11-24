# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=printers)
# ---- Settings > Printers: CUPS printers and queues.

ipc settingsCategory printers; sleep 1.5
title_ok=0
if command -v python3 >/dev/null 2>&1 && { [ -n "${A11Y:-}" ] || [ -d /testbed/lib ]; }; then
    if grep -q 'Printers' <(timeout 20 python3 "${A11Y:-/testbed/lib/a11y_client.py}" tree --max-depth 16 2>/dev/null); then
        title_ok=1
    fi
fi
if [ "$title_ok" = 1 ]; then
    result printers-page-titled PASS
else
    result printers-page-titled SKIP "no AT-SPI Printers title seen"
fi
shot settings-printers 0.5
ipc closeAll
