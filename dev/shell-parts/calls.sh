# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=calls)
# ---- Calls: the native window, with stand-ins behind it. No landline, no modem
#      and no phone here. The history is seeded from calls.json because no
#      backend logs a dialled call in the dev container; the Call button is only
#      checked as a button. The caller card is a file written by
#      dev/fake-phone-call.py; Answer/Decline go through `ipc callAction`.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
CALL_TOOL=/work/dev/fake-phone-call.py
ACTIONS=/tmp/phone-call-actions
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/shani-shell"
CONTACTS="$DATA_HOME/contacts"
CALLS_FILE="$DATA_HOME/calls.json"
CALLS_BACKUP=/tmp/calls-part-backup.json

# a contact whose number is the caller's, so a few typed digits suggest a name
mkdir -p "$CONTACTS"
cat > "$CONTACTS/call-test-asha.vcf" <<'VCF'
BEGIN:VCARD
VERSION:4.0
UID:urn:uuid:call-test-asha
FN:Asha Patil
N:Patil;Asha;;;
TEL;TYPE=CELL:9844444444
END:VCARD
VCF

# one SIP line so the pad has a line to pick; the stand-in account is local only
python3 - <<'PY'
import json, os
p = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
                 "shani-shell", "sip-accounts.json")
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump({"accounts": [{"id": "calltest01", "name": "Test line",
                         "username": "calltest01", "password": "offline",
                         "domain": "example.invalid", "port": 5060,
                         "transport": "udp", "enabled": False, "register": False}]},
          open(p, "w"))
PY

# one history row, moved aside at the end: link-apps.sh still expects an empty
# history, and the full suite sources every part in one session.
rm -f "$CALLS_BACKUP"
if [ -f "$CALLS_FILE" ]; then cp "$CALLS_FILE" "$CALLS_BACKUP"; else : > "$CALLS_BACKUP.none"; fi
mkdir -p "$DATA_HOME"
python3 - "$CALLS_FILE" <<'PY'
import json, sys, time
json.dump([{"id": "call-test-row", "line": "phone", "number": "9844444444",
            "name": "Asha Patil", "direction": "in", "missed": False,
            "when": int(time.time()), "seconds": 95}], open(sys.argv[1], "w"))
PY

# the backends resolve the seeded contact from digits before any window opens
python3 /work/bridge/link.py contacts 98444 2>/dev/null | grep -q 'Asha Patil' \
    && result calls-contact-by-digits PASS \
    || result calls-contact-by-digits FAIL "$(python3 /work/bridge/link.py contacts 98444 2>&1)"

rm -f "$ACTIONS"
python3 "$CALL_TOOL" clear

# ---- open, read the history, draw the pad --------------------------------------
ipc callsOpen ""
waitfor "d['callsShown'] == True" 8 && result calls-opens PASS \
    || result calls-opens FAIL "$(q "['callsShown']")"
# the count comes from the seeded row, not from pressing Call: no backend in the
# dev container writes a dialled call to the history.
waitfor "d['callsCount'] > 0" 8 && result calls-history-seeded PASS \
    || result calls-history-seeded FAIL "$(q "['callsCount']")"

if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" find "text:^A number$" >/dev/null 2>&1 \
        && result calls-dial-pad PASS || result calls-dial-pad FAIL "the number field was not announced"
else
    result calls-dial-pad SKIP "no accessibility client"
fi

# the line chips come from link.py state; the seeded account is one of them
waitfor "'sip-calltest01' in str(d['callsLines'])" 8 && result calls-lines-listed PASS \
    || result calls-lines-listed FAIL "$(q "['callsLines']")"

# ---- pick a line, type a number, press Call ------------------------------------
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "radio button:^sip-calltest01$" >/dev/null 2>&1 \
        && result calls-line-pickable PASS || result calls-line-pickable FAIL "the line chip was not pressable"
    timeout 20 python3 "$A11Y" press "text:^A number$" >/dev/null 2>&1
    wtype "98444"
    # the suggestion is the proof the digits reached the pad
    timeout 20 python3 "$A11Y" find "Asha Patil" >/dev/null 2>&1 \
        && result calls-suggests-contact PASS \
        || result calls-suggests-contact FAIL "no contact suggested for 98444"
    timeout 20 python3 "$A11Y" press "button:^Call$" >/dev/null 2>&1 \
        && result calls-call-button PASS \
        || result calls-call-button FAIL "the Call button was not pressable"
else
    result calls-line-pickable SKIP "no accessibility client"
    result calls-suggests-contact SKIP "no accessibility client"
    result calls-call-button SKIP "no accessibility client"
    ipc phoneOpen 9844444444       # the same pad, addressed by number
fi

# ---- an incoming call: a card with the caller's name ---------------------------
python3 "$CALL_TOOL" post "Asha Patil" 9844444444 c1 phone
waitfor "d['incoming'] == 'Asha Patil' and d['incomingId'] == 'c1'" 10 \
    && result calls-incoming-card PASS \
    || result calls-incoming-card FAIL "$(q "['incoming'], d['incomingId']")"
shot calls-incoming 0.3

ipc callAction c1 answer
waitfor "not d['incoming'] and d['incomingId'] != 'c1'" 8 \
    && result calls-answer-clears-card PASS \
    || result calls-answer-clears-card FAIL "$(q "['incoming'], d['incomingId']")"
grep -q '^c1 answer$' "$ACTIONS" 2>/dev/null \
    && result calls-answer-recorded PASS || result calls-answer-recorded FAIL "$(cat "$ACTIONS" 2>&1)"

# ---- and a second caller, declined ---------------------------------------------
python3 "$CALL_TOOL" post "Ravi Shah" 9911111111 c2 phone
waitfor "d['incoming'] == 'Ravi Shah' and d['incomingId'] == 'c2'" 10 \
    && result calls-second-card PASS \
    || result calls-second-card FAIL "$(q "['incoming'], d['incomingId']")"
ipc callAction c2 decline
waitfor "not d['incoming'] and d['incomingId'] != 'c2'" 8 \
    && result calls-decline-clears-card PASS \
    || result calls-decline-clears-card FAIL "$(q "['incoming'], d['incomingId']")"
grep -q '^c2 decline$' "$ACTIONS" 2>/dev/null \
    && result calls-decline-recorded PASS || result calls-decline-recorded FAIL "$(cat "$ACTIONS" 2>&1)"

ipc callsClose
waitfor "d['callsShown'] == False" 6 && result calls-closes PASS \
    || result calls-closes FAIL "$(q "['callsShown']")"
python3 "$CALL_TOOL" clear
# leave the history as it was found, for the other parts in the same session
if [ -f "$CALLS_BACKUP.none" ]; then
    rm -f "$CALLS_FILE" "$CALLS_BACKUP.none"
else
    cp "$CALLS_BACKUP" "$CALLS_FILE"
fi
rm -f "$CALLS_BACKUP"
