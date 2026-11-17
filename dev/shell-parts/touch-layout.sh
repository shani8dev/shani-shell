# Shared controls and a crowded app toolbar, on a touch-first screen.
if [ -z "${SHANI_FORM_FACTOR:-}" ] || [ "${SHANI_FORM_FACTOR:-}" = phone ]; then
    settings '{"formFactors":{"winit":"phone"}}'
    ipc textEditorNew
    waitfor "d['textEditor']" 4
    shot touch-layout-editor 0.5
    a11y=/testbed/lib/a11y_client.py
    if [ -f "$a11y" ]; then
        control=$(python3 "$a11y" find 'button:^Save$' 2>&1)
        printf '%s\n' "$control" | python3 -c '
import re, sys
matches = re.findall(r"@(-?\d+),(-?\d+) (\d+)x(\d+)", sys.stdin.read())
assert matches, "Save button not exposed on screen"
assert any(int(w) >= 44 and int(h) >= 44 for x, y, w, h in matches), matches
' && result touch-layout-save-target PASS || result touch-layout-save-target FAIL "$control"

        # KeyFocus must scroll horizontal toolbars as well as vertical lists.
        wtype -k F6
        sleep 0.2
        i=0
        until q "['navFocus'].startswith('Larger text')" | grep -q True || [ "$i" -ge 50 ]; do
            wtype -k Right
            sleep 0.05
            i=$((i+1))
        done
        control=$(python3 "$a11y" find 'button:^Larger text' 2>&1)
        printf '%s\n' "$control" | grep -q '@' \
            && result touch-layout-last-tool-reachable PASS \
            || result touch-layout-last-tool-reachable FAIL "$control; focused: $(q "['navFocus']")"
    else
        result touch-layout-accessibility FAIL "accessibility client not installed"
    fi
    ipc textEditorClose
    ipc launcher "Files"
    waitfor "d['osk'] and d['oskHeight'] > 0 and d['textFocus']" 5 \
        && result touch-layout-keyboard-follows-search PASS || result touch-layout-keyboard-follows-search FAIL
    gap=$(q "['launcherBottomGap']")
    height=$(q "['oskHeight']")
    python3 -c 'import sys; gap=float(sys.argv[1]); kb=float(sys.argv[2]); sys.exit(0 if gap >= kb else 1)' "$gap" "$height" \
        && result touch-layout-results-stay-above-keyboard PASS "gap $gap, keyboard $height" \
        || result touch-layout-results-stay-above-keyboard FAIL "gap $gap, keyboard $height"
    shot touch-layout-keyboard 0.5
    ipc closeAll
    waitfor "not d['osk'] and d['oskHeight'] == 0" 5 \
        && result touch-layout-keyboard-goes-with-search PASS || result touch-layout-keyboard-goes-with-search FAIL
    settings '{}'
fi
