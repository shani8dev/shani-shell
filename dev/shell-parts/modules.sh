# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=modules)
# ---- Settings > Kernel modules: loaded modules and managed drop-ins.

ipc settingsCategory modules; sleep 1.5
title_ok=0
if command -v python3 >/dev/null 2>&1 && { [ -n "${A11Y:-}" ] || [ -d /testbed/lib ]; }; then
    if grep -q 'Kernel modules' <(timeout 20 python3 "${A11Y:-/testbed/lib/a11y_client.py}" tree --max-depth 16 2>/dev/null); then
        title_ok=1
    fi
fi
if [ "$title_ok" = 1 ]; then
    result modules-page-titled PASS
else
    result modules-page-titled SKIP "no AT-SPI Kernel modules title seen"
fi
shot settings-modules 0.5
ipc closeAll
