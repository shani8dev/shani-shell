# sourced by dev/shell-test.sh (or alone: CHRONOA=real sh dev/check.sh shell=chronoa-real)
# ---- the real Chronoa, answering through the shell (CHRONOA=real; the suite's mock otherwise) ----
# dev/session.sh starts ../shani-chronoa's app; the shell's bridge reaches its
# dev.shani.chronoa.Agent, and the model is this machine's llama-server
if [ "${CHRONOA:-mock}" != real ]; then
    result chronoa-real-answers SKIP "the mock is running (CHRONOA=real uses the real Chronoa)"
else
    ipc ask "Reply with exactly five words: what colour is the sky?"
    waitfor "d['chronoa'] in ('idle', 'ready') and 'blue' in d['chronoaReply'].lower()" 180 \
        && result chronoa-real-answers PASS "$(q "['chronoaReply']" | tr '\n' ' ' | cut -c1-80)" \
        || result chronoa-real-answers FAIL "state $(q "['chronoa']"), reply '$(q "['chronoaReply']" | tr '\n' ' ' | cut -c1-120)'; $(grep -E 'ERROR|Traceback' /work/out/logs/chronoa.log | tail -1 | cut -c1-160)"
    # what foot's Ctrl+Shift+A sends: a command's output, explained by the real model
    printf 'bash: gti: command not found\n' | SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani chronoa explain - >/dev/null 2>&1
    waitfor "d['chronoa'] in ('idle', 'ready') and len(d['chronoaReply']) > 40" 240 \
        && result chronoa-real-explains-output PASS "$(q "['chronoaReply']" | tr '\n' ' ' | cut -c1-100)" \
        || result chronoa-real-explains-output FAIL "state $(q "['chronoa']"), reply '$(q "['chronoaReply']" | tr '\n' ' ' | cut -c1-120)'"
    ipc closeChronoa; ipc closeAll
    # writing tools through the real Agent.Write: proofread, by the model
    printf 'teh cat sat on teh mat' | wl-copy --primary
    ipc writingTools; waitfor "d['writingSource'] != ''" 5
    ipc writingToolsChoose 0
    waitfor "not d['writingBusy'] and (d['writingResult'] != '' or d['writingError'] != '')" 200
    r=$(q "['writingResult']")
    echo "$r" | grep -qi "the cat sat on the mat" && result chronoa-real-proofreads PASS "$r" \
        || result chronoa-real-proofreads FAIL "result '$r' error '$(q "['writingError']")'"
    shot writing-tools-real 0.2
    ipc writingToolsClose
    # suggested replies, written by the model
    python3 /work/dev/reply-client.py "Are you coming to dinner tonight?" >/dev/null 2>&1 &
    waitfor "any(s.startswith('Are you coming to dinner') for s in d['smartReplies'])" 200 \
        && result chronoa-real-suggests-replies PASS "$(q "['smartReplies']" | cut -c1-140)" || result chronoa-real-suggests-replies FAIL "$(q "['smartReplies']")"
    shot smart-replies-real 0.2
    # a name for a file, from its words
    mkdir -p /tmp/real-name; printf 'Electricity bill for March 2026 from City Power Ltd. Amount due: 1,240.00\n' > /tmp/real-name/scan0001.txt
    ipc filesSuggestName /tmp/real-name/scan0001.txt
    waitfor "not d['naming'] and (d['nameSuggestion'] != '' or d['nameError'] != '')" 200
    s=$(q "['nameSuggestion']")
    echo "$s" | grep -qi "electric\|bill\|power" && echo "$s" | grep -q "\.txt$" && result chronoa-real-names-a-file PASS "$s" || result chronoa-real-names-a-file FAIL "'$s' error '$(q "['nameError']")'"
fi
