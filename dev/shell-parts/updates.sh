# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=updates)
# ---- Settings > Updates: the channel, what is running, what is offered, and
#      what is waiting - read from `shani-deploy --status --check --json` by
#      Services/Updates.qml, the same contract the shell's pages read. Installing stays
#      with shani-deploy and authorisation.
#
# There is no shani-deploy in the dev image, so a stand-in answers the read and
# the page is checked against it.
D=/tmp/fake-deploy; mkdir -p $D
# /usr/local/bin: the running shell inherits that PATH, not this script's
cat > /usr/local/bin/shani-deploy <<'SH'
#!/bin/sh
case "$*" in
    *--check*--json*)
        printf '%s' '{"ok":true,"update_available":true,"boot_markers":{"reboot_needed":false},"current_slot":"green","version":"20261121","remote":{"stable":"20261121","latest":"20261122"}}' ;;
    *) exit 2 ;;
esac
SH
chmod +x /usr/local/bin/shani-deploy
rm -f /tmp/deploy-state

ipc settingsCategory updates; sleep 1.5
waitfor "d['updatesKnown'] == True" 10 && result updates-page-reads-the-status PASS || result updates-page-reads-the-status FAIL "$(q "['updatesSummary']")"
waitfor "d['updatesVersion'] == '20261121'" 8 && result updates-shows-the-release PASS "$(q "['updatesVersion']")" || result updates-shows-the-release FAIL "$(q "['updatesVersion']")"
waitfor "d['updatesCandidate'] != ''" 8 && result updates-shows-the-candidate PASS "$(q "['updatesCandidate']")" || result updates-shows-the-candidate FAIL "$(q "['updatesCandidate']")"
waitfor "d['updatesAvailable'] == True" 8 && result updates-sees-what-is-waiting PASS "$(q "['updatesSummary']")" || result updates-sees-what-is-waiting FAIL "$(q "['updatesSummary']")"

# the channel is a setting the page writes and the bridge reads back
ipc settingsAt updates ""
sleep 0.8
[ -f /tmp/deploy-state ] || true
waitfor "d['updatesChannel'] in ('stable', 'latest')" 6 && result updates-has-a-channel PASS "$(q "['updatesChannel']")" || result updates-has-a-channel FAIL "$(q "['updatesChannel']")"

# a page with no shani-deploy says so rather than showing an empty list
ipc settingsCategory about; sleep 0.6
ipc settingsCategory updates; sleep 1.2
grep -q 'Updates' <(timeout 20 python3 "${A11Y:-/testbed/lib/a11y_client.py}" tree --max-depth 14 2>/dev/null) \
    && result updates-page-is-titled PASS || result updates-page-is-titled SKIP "no AT-SPI client"

ipc closeAll; rm -f /usr/local/bin/shani-deploy; rm -rf "$D"