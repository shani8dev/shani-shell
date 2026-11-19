# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=users-remove)
# ---- Settings > Users: removing an account with its files needs its name typed ----
# The page loads with a second account listed, so its row - the Remove buttons and
# the typed-name field - is made; any QML error in it lands in qs.log, which
# shell-test.sh fails on. The rule itself (the button enabled only for the exact
# name) is held in tests/test_qml_patterns.py.
id meera >/dev/null 2>&1 || useradd -m -u 1500 -c "Meera" -s /bin/bash meera
ipc settingsAt users ""; sleep 1.5; shot users-page 0.2
grep -q 'Remove with their files' /work/shani/Modules/Settings/SettingsUsers.qml \
    && ! grep -aE 'SettingsUsers\.qml:[0-9]+' /work/out/logs/qs.log \
    && result users-page-loads-clean PASS || result users-page-loads-clean FAIL "$(grep -a 'SettingsUsers' /work/out/logs/qs.log | tail -3)"
ipc closeAll
userdel -r meera 2>/dev/null || true
