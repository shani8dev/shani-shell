# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=niri-config-undo)
# ---- a niri include niri cannot read is put back (NiriConfig), and the person told ----------
f=/root/.config/niri/shani-input.kdl
settings '{"cursorTheme": "Adwaita"}'
waitfor "d['niriConfigPending'] == 0" 6; sleep 0.5
[ -f "$f" ] && [ ! -f "$f.prev" ] && grep -q 'xcursor-theme "Adwaita"' "$f" \
    && result niri-config-kept-when-loaded PASS || result niri-config-kept-when-loaded FAIL "$(ls "$f"* 2>&1 | tr '\n' ' ')"
cp "$f" /tmp/input-good.kdl
u0=$(q "['niriConfigUndone']")
# a quote in a name: the shell writes an include niri cannot parse
settings '{"cursorTheme": "Bad\"Theme"}'
back() { i=0; until [ "$(cat "$f")" = "$(cat /tmp/input-good.kdl)" ] && [ ! -f "$f.prev" ] || [ $i -ge 16 ]; do sleep 0.25; i=$((i+1)); done; [ $i -lt 16 ]; }
waitfor "d['niriConfigUndone'] == $u0 + 1" 8 && back \
    && result niri-config-undone PASS || result niri-config-undone FAIL "undone $(q "['niriConfigUndone']"); $(grep xcursor-theme "$f"); $(ls "$f"* | tr '\n' ' ')"
waitfor "'A change could not be applied' in d['notificationSummaries']" 4 \
    && result niri-config-undone-told PASS || result niri-config-undone-told FAIL "$(q "['notificationSummaries'][-3:]")"
grep -q "Error\|error" /work/out/logs/niri.log && niri validate -c /work/dev/niri/session.kdl >/dev/null 2>&1 \
    && result niri-config-valid-after-undo PASS || result niri-config-valid-after-undo FAIL "$(niri validate -c /work/dev/niri/session.kdl 2>&1 | tail -3)"
settings '{}'
