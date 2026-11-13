# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=smart-replies)
# ---- suggested replies on a message notification (SmartReplies -> Agent.Write) ----
# the mock's Write answers "[suggest] <text>", so the message's own lines come
# back as the chips: the second is the message body, "Reached the station"
rm -f /tmp/smart-replied
python3 /work/dev/reply-client.py "Message from Ravi" > /tmp/smart-replied 2>&1 &
waitfor "any(s.startswith('Message from Ravi:') for s in d['smartReplies'])" 8 \
    && result smart-replies-suggested PASS "$(q "['smartReplies']" | cut -c1-120)" || result smart-replies-suggested FAIL "$(q "['smartReplies']")"
sleep 0.5; shot smart-replies 0.2
ipc notificationSuggestedReply "Message from Ravi" 1
for i in $(seq 1 20); do [ -s /tmp/smart-replied ] && break; sleep 0.25; done
[ "$(cat /tmp/smart-replied)" = "Reached the station" ] && result smart-replies-one-click-sends PASS || result smart-replies-one-click-sends FAIL "the app got '$(cat /tmp/smart-replied)'"
# hidden content: nothing is suggested (it would show the message, and send it to the model)
settings '{"notifHideContent": true}'
python3 /work/dev/reply-client.py "Message from Meera" >/dev/null 2>&1 &
sleep 3
q "['smartReplies']" | grep -q "Message from Meera" && result smart-replies-not-for-hidden FAIL || result smart-replies-not-for-hidden PASS
settings '{}'
