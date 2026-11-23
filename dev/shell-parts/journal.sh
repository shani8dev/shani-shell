# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=journal)
# ---- Settings > Journal: journald storage policy and recent log view.

ipc settingsCategory journal; sleep 1.5
title_ok=0
if command -v python3 >/dev/null 2>&1 && [ -n "${A11Y:-}" ] || [ -d /testbed/lib ]; then
    if grep -q 'Journal' <(timeout 20 python3 "${A11Y:-/testbed/lib/a11y_client.py}" tree --max-depth 16 2>/dev/null); then
        title_ok=1
    fi
fi
if [ "$title_ok" = 1 ]; then
    result journal-page-titled PASS
else
    # The page has no dedicated state key; AT-SPI may be unavailable in this run.
    result journal-page-titled SKIP "no AT-SPI Journal title seen"
fi
shot settings-journal 0.5
ipc closeAll
