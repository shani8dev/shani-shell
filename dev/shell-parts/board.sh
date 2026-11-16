# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=board)
# ---- the classroom board (docs/FORM-FACTORS.md step 6) ----
# The dev screen chosen as a board: everything 1.4 times larger; the whiteboard
# written on in two pages (lines through the IPC - a nested niri has no finger
# or pen) and saved as one PDF of two pages in Documents/Whiteboards.
if [ -z "${SHANI_FORM_FACTOR:-}" ]; then
    settings '{"formFactors": {"winit": "board"}}'
    waitfor "d['formFactor'] == 'board' and abs(d['uiScale'] - 1.4) < 0.01" 5 \
        && result board-scale PASS || result board-scale FAIL "$(q "['formFactor'], d['uiScale']")"
    # the bar is at the bottom on a board, within reach of someone standing at
    # it; the owner can still put it back at the top
    waitfor "d['barEdge'] == 'bottom'" 5 && result board-bar-at-the-bottom PASS \
        || result board-bar-at-the-bottom FAIL "$(q "['barEdge']")"
    shot board-bar 0.4
    settings '{"formFactors": {"winit": "board"}, "barEdge": "top"}'
    waitfor "d['barEdge'] == 'top'" 5 && result board-bar-edge-is-the-owners PASS \
        || result board-bar-edge-is-the-owners FAIL "$(q "['barEdge']")"
    settings '{"formFactors": {"winit": "board"}}'
    rm -rf /root/Documents/Whiteboards
    ipc whiteboard true
    waitfor "d['whiteboard']" 3
    ipc whiteboardLine 200 200 900 420
    ipc whiteboardLine 300 500 700 520
    waitfor "d['whiteboardStrokes'] == 2" 3 && result board-whiteboard-strokes PASS || result board-whiteboard-strokes FAIL "$(q "['whiteboardStrokes']")"
    shot board-whiteboard 0.4
    ipc whiteboardNewPage
    ipc whiteboardLine 400 300 800 300
    waitfor "d['whiteboardPage'] == 1 and d['whiteboardStrokes'] == 3" 3 \
        && result board-whiteboard-pages PASS || result board-whiteboard-pages FAIL "$(q "['whiteboardPage'], d['whiteboardStrokes']")"
    ipc whiteboardSave
    waitfor "d['whiteboardSaved'] != ''" 10
    f=$(q "['whiteboardSaved']")
    pages=$(python3 -c "import sys, pymupdf; print(len(pymupdf.open(sys.argv[1])))" "$f" 2>/dev/null)
    [ "$pages" = 2 ] && case "$f" in /root/Documents/Whiteboards/*.pdf) true;; *) false;; esac \
        && result board-whiteboard-saved-as-pdf PASS "${f##*/}" || result board-whiteboard-saved-as-pdf FAIL "'$f' pages=$pages"
    ipc whiteboard false
    waitfor "not d['whiteboard']" 3
    settings '{}'
    waitfor "d['formFactor'] == 'computer'" 5
fi
