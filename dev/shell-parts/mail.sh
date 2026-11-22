# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=mail)
# ---- the mail reader against a stand-in MailHog (dev/fake-mailhog.py): the
#      list comes from the API, a message opens with its body, and a message
#      sent through SMTP lands in the list. A real account (IMAP) is not in the
#      dev image - the bridge's IMAP path is exercised in bridge's own tests.
MH=${SHANI_MAIL_MAILHOG_PORT:-8025}
CONF=/root/.config/shani-shell/mail.json

python3 /work/dev/fake-mailhog.py "$MH" >/dev/null 2>&1 &
MH_PID=$!
trap 'kill $MH_PID 2>/dev/null' EXIT
sleep 0.8

mkdir -p "$(dirname "$CONF")"
cat > "$CONF" <<JSON
{"kind": "mailhog", "mailhog": {"url": "http://127.0.0.1:$MH"},
 "account": {"name": "Shani Tester", "email": "shani@example.com"}}
JSON

ipc mailOpen; sleep 1.8

waitfor "d['mailKind'] == 'mailhog'" 6 && result mail-reads-the-server PASS || result mail-reads-the-server FAIL "$(q "['mailKind']")"
waitfor "d['mailCount'] == 2" 8 && result mail-lists-the-messages PASS "$(q "['mailCount']")" || result mail-lists-the-messages FAIL "$(q "['mailCount']")"
waitfor "d['mailSubject'] == 'Welcome to Shani'" 8 && result mail-opens-a-message PASS "$(q "['mailSubject']")" || result mail-opens-a-message FAIL "$(q "['mailSubject']")"
waitfor "'Shani Team' in d['mailFrom']" 6 && result mail-shows-the-sender PASS "$(q "['mailFrom']")" || result mail-shows-the-sender FAIL "$(q "['mailFrom']")"
waitfor "d['mailBody'] != ''" 6 && result mail-shows-the-body PASS "$(q "['mailBody']")" || result mail-shows-the-body FAIL "$(q "['mailBody']")"

# a message sent the way any program sends one: SMTP, onto the stand-in's sink,
# then read back through the reader's list
python3 - <<PY
import smtplib
from email.message import EmailMessage
m = EmailMessage()
m["From"] = "someone@example.com"
m["To"] = "shani@example.com"
m["Subject"] = "Sent from the test"
m.set_content("This arrived over SMTP.")
with smtplib.SMTP("127.0.0.1", 1025) as s:
    s.send_message(m)
PY
ipc mailToggle; sleep 0.6; ipc mailOpen
waitfor "d['mailCount'] == 3" 10 && result mail-sees-a-new-message PASS "$(q "['mailCount']")" || result mail-sees-a-new-message FAIL "$(q "['mailCount']")"

shot mail-list 0.3
# ---- the message as it was sent: HTML rendered, remote images taken out -----
waitfor "d['mailAttachments'] == ['readme.txt']" 6 \
    && result mail-lists-attachments PASS "$(q "['mailAttachments']")" || result mail-lists-attachments FAIL "$(q "['mailAttachments']")"
waitfor "d['mailShowHtml'] == True" 6 && result mail-shows-html PASS || result mail-shows-html FAIL "html $(q "['mailHtml']") chars, showHtml $(q "['mailShowHtml']")"

# a word in the body, not in the title: the server (or the reader) finds it
ipc mailSearch "say hello"
i=0
until [ "$(q "['mailQuery']")" = "say hello" ] || [ $i -ge 24 ]; do sleep 0.25; i=$((i+1)); done
waitfor "d['mailQuery'] == 'say hello' and d['mailSubject'] == 'Welcome to Shani'" 8 \
    && result mail-search-finds-in-the-body PASS "$(q "['mailSubject']")" || result mail-search-finds-in-the-body FAIL "query $(q "['mailQuery']"), subject $(q "['mailSubject']")"
ipc mailSearch "nothing-like-this-is-here"
i=0
until [ "$(q "['mailCount']")" = 0 ] || [ $i -ge 24 ]; do sleep 0.25; i=$((i+1)); done
[ "$(q "['mailCount']")" = 0 ] && result mail-search-finds-nothing PASS || result mail-search-finds-nothing FAIL "$(q "['mailCount']")"
ipc mailSearch ""
ipc mailClose
rm -f "$CONF"
