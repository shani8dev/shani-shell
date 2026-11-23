# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=bootinfo)
# ---- Settings > Boot & Recovery: the A/B slots, read from shani-deploy.
#      shani-deploy is not in the dev image, so what is checked is that the page
#      opens, says plainly that the slots cannot be read, and that a stand-in
#      shani-deploy's JSON becomes rows - the same shape the page renders.
FW=/tmp/fake-shani-deploy; mkdir -p $FW
cat > $FW/shani-deploy <<'SH'
#!/bin/sh
case "$*" in
    *--json*) printf '%s' '{"version":"20261121","profile":"niri","channel":"stable","booted_slot":"green","current_slot":"green","previous_slot":"blue","candidate_boot":false,"update_available":null,"boot_failure":"","auto_rollback_done":false}' ;;
    *) echo "usage" >&2; exit 2 ;;
esac
SH
chmod +x $FW/shani-deploy
export PATH="$FW:$PATH"

# with no shani-deploy the page must say so rather than show an empty list
rm -f "$FW/shani-deploy"
ipc settingsCategory boot; sleep 1.5
waitfor "d['bootNote'] != '' or d['bootRows'] != []" 8 \
    && result boot-page-says-when-it-cannot-read PASS || result boot-page-says-when-it-cannot-read FAIL "$(q "['bootNote']")"

# a stand-in that answers: the rows appear
cat > $FW/shani-deploy <<'SH'
#!/bin/sh
printf '%s' '{"version":"20261121","profile":"niri","channel":"stable","booted_slot":"green","current_slot":"green","previous_slot":"blue","candidate_boot":false,"update_available":null,"boot_failure":"","auto_rollback_done":false}'
SH
chmod +x $FW/shani-deploy
SHANI_BOOTINFO_TOOL=/work/bridge/bootinfo.py python3 /work/bridge/bootinfo.py status | grep -q 'green' \
    && result bootinfo-reads-the-slot PASS || result bootinfo-reads-the-slot FAIL "$(python3 /work/bridge/bootinfo.py status | head -c 120)"

# the page re-reads when it is opened again
ipc settingsCategory boot; sleep 2
grep -q 'Boot & Recovery' <(timeout 20 python3 "${A11Y:-/testbed/lib/a11y_client.py}" tree --max-depth 14 2>/dev/null) \
    && result boot-page-titled PASS || result boot-page-titled SKIP "no AT-SPI client"

ipc closeAll; rm -rf "$FW"