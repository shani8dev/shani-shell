# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=niri-config-undo)
# ---- a niri include niri cannot read is put back (NiriConfig), and the person told ----------
f=/root/.config/niri/shani-input.kdl
settings '{"cursorTheme": "Adwaita"}'
waitfor "d['niriConfigPending'] == 0" 6; sleep 0.5
[ -f "$f" ] && [ ! -f "$f.prev" ] && grep -q 'xcursor-theme "Adwaita"' "$f" \
    && result niri-config-kept-when-loaded PASS || result niri-config-kept-when-loaded FAIL "$(ls "$f"* 2>&1 | tr '\n' ' ')"
cp "$f" /tmp/input-good.kdl
u0=$(q "['niriConfigRejected']")
# a quote in a name: the shell refuses it before writing (niri validate on a
# candidate beside the real file), so the live file is never broken and there is
# nothing to put back
settings '{"cursorTheme": "Bad\"Theme"}'
waitfor "d['niriConfigRejected'] == $u0 + 1" 8 \
    && result niri-config-refused-before-writing PASS "$(q "['niriConfigRejected']")" \
    || result niri-config-refused-before-writing FAIL "rejected $(q "['niriConfigRejected']") of $(q "['niriConfigPending']") pending"
# ...and the file on disk is exactly as it was
[ "$(cat "$f")" = "$(cat /tmp/input-good.kdl)" ] && [ ! -f "$f.prev" ] \
    && result niri-config-unchanged PASS || result niri-config-unchanged FAIL "$(ls "$f"* | tr '\n' ' ')"
waitfor "'The change was not applied' in d['notificationSummaries']" 4 \
    && result niri-config-told PASS || result niri-config-told FAIL "$(q "['notificationSummaries'][-3:]")"
# a change niri does accept is written and needs no undo
settings '{"cursorTheme": "Adwaita"}'
waitfor "d['niriConfigPending'] == 0" 6; sleep 0.5
grep -q 'xcursor-theme "Adwaita"' "$f" && [ ! -f "$f.prev" ] \
    && result niri-config-kept-when-applied PASS || result niri-config-kept-when-applied FAIL "$(ls "$f"* | tr '\n' ' ')"
grep -q "Error\|error" /work/out/logs/niri.log && niri validate -c /work/dev/niri/session.kdl >/dev/null 2>&1 \
    && result niri-config-valid-after-undo PASS || result niri-config-valid-after-undo FAIL "$(niri validate -c /work/dev/niri/session.kdl 2>&1 | tail -3)"
settings '{}'
