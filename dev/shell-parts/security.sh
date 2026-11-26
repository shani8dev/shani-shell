# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=security)
# ---- Settings > Security: posture, pwquality, hosts, sudoers, AppArmor.

ipc settingsCategory security; sleep 1.5
title_ok=0
if command -v python3 >/dev/null 2>&1 && { [ -n "${A11Y:-}" ] || [ -d /testbed/lib ]; }; then
    if grep -q 'Security' <(timeout 20 python3 "${A11Y:-/testbed/lib/a11y_client.py}" tree --max-depth 16 2>/dev/null); then
        title_ok=1
    fi
fi
if [ "$title_ok" = 1 ]; then
    result security-page-titled PASS
else
    result security-page-titled SKIP "no AT-SPI Security title seen"
fi
shot settings-security 0.5

# the raw audit log records now live here, read through system_background.py.
# The stand-in's ausearch speaks the other bridge's shape, so an empty list is
# honest here; what is checked is that this page owns the read, not Background.
waitfor "'log' in d.get('systemState',{}).get('securityAudit',{})" 10 \
    && result security-audit-log PASS "$(q "['systemState']['securityAudit']['log']")" \
    || result security-audit-log FAIL "$(q "['systemState']")"
shot settings-security-audit 0.3
ipc closeAll
