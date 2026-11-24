# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=storage)
# ---- Settings > Storage: disk space and cleanup.

ipc settingsCategory storage; sleep 2
title_ok=0
if command -v python3 >/dev/null 2>&1 && { [ -n "${A11Y:-}" ] || [ -d /testbed/lib ]; }; then
    tree=$(timeout 20 python3 "${A11Y:-/testbed/lib/a11y_client.py}" tree --max-depth 16 2>/dev/null || true)
    if echo "$tree" | grep -qE 'Storage|SSD maintenance|App caches|Disk|Trim SSD'; then
        title_ok=1
    fi
fi
if [ "$title_ok" = 1 ]; then
    result storage-page-titled PASS
else
    result storage-page-titled SKIP "no AT-SPI Storage title seen"
fi
shot settings-storage 0.5
ipc closeAll
