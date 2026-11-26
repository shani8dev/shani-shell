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

# The other three tabs read bridge/phone_tools.py. One stand-in answers music,
# files, remote, link and audio from one state file, and the bridge logs each
# ask. Parent wires the same SHANI_* overrides into the shell's own process;
# exporting them here also checks the bridge calls made by this part.
PHONE_TOOLS_FAKE=/work/dev/fake-phone-tools.py
export SHANI_PHONE_TOOLS_STATE=/tmp/fake-phone-tools.json
export SHANI_PHONE_TOOLS_LOG=/tmp/fake-phone-tools-calls
export SHANI_MUSIC="python3 $PHONE_TOOLS_FAKE music"
export SHANI_FILES_SEND="python3 $PHONE_TOOLS_FAKE files-send"
export SHANI_FILES_LOG=/tmp/fake-phone-files-calls
export SHANI_PHONE_REMOTE="python3 $PHONE_TOOLS_FAKE remote"
export SHANI_PHONE_REMOTE_LOG=/tmp/fake-phone-remote-calls
export SHANI_PHONE_LINK="python3 $PHONE_TOOLS_FAKE link"
export SHANI_PHONE_LINK_LOG=/tmp/fake-phone-link-calls
export SHANI_AUDIO="python3 $PHONE_TOOLS_FAKE audio"
export SHANI_AUDIO_LOG=/tmp/fake-phone-audio-calls
export SHANI_FILES_DIR=/tmp/fake-phone-files-inbox
mkdir -p "$SHANI_FILES_DIR"
printf 'a received photo\n' > "$SHANI_FILES_DIR/Asha-photo.jpg"
printf 'a file to send\n' > /tmp/calls-send.txt
rm -f "$SHANI_PHONE_TOOLS_STATE" "$SHANI_PHONE_TOOLS_LOG" "$SHANI_FILES_LOG" \
      "$SHANI_PHONE_REMOTE_LOG" "$SHANI_PHONE_LINK_LOG" "$SHANI_AUDIO_LOG"
python3 "$PHONE_TOOLS_FAKE" seed
python3 /work/bridge/phone_tools.py music status 2>/dev/null | grep -q 'Mono Train' \
    && result calls-phone-tools-bridge PASS \
    || result calls-phone-tools-bridge FAIL "$(python3 /work/bridge/phone_tools.py music status 2>&1)"

phone_press() {
    for label in "$@"; do
        timeout 20 python3 "$A11Y" press "$label" >/dev/null 2>&1 && return 0
    done
    return 1
}

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

# ---- the line's service is started by D-Bus activation ----------------------
# The shipped data/dbus file and the systemd user unit both name this bus
# name. session.sh installs the activation file against the private bus; no
# part of the session starts the service by hand. A plain method call must
# therefore bring it up and answer with the seeded line, and only one process
# may own the line. SHANI_PHONE_NO_DEVICES keeps it off real hardware.
SERVICE=dev.shani.Shell.Phone
CALLS_PATH=/dev/shani/Shell/Phone/Calls
before=absent
busctl --user status "$SERVICE" >/dev/null 2>&1 && before=present
activated=$(timeout 40 gdbus call --session --dest "$SERVICE" \
    --object-path "$CALLS_PATH" --method "$SERVICE.Calls.Lines" 2>&1)
arc=$?
[ "$arc" = 0 ] && printf '%s' "$activated" | grep -q 'sip-calltest01' \
    && result calls-service-activates PASS "owner was $before before the call" \
    || result calls-service-activates FAIL "$activated"
owners=$(busctl --user list --no-pager 2>/dev/null | grep -c '^dev\.shani\.Shell\.Phone' || true)
[ "$owners" = 1 ] \
    && result calls-service-single-owner PASS "$(busctl --user status "$SERVICE" --no-pager 2>/dev/null | tail -1)" \
    || result calls-service-single-owner FAIL "$owners owners of $SERVICE"

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

# ---- the status header, the drawn pad and the address book -------------------
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" find "Ready" >/dev/null 2>&1 \
        && result calls-status-header PASS || result calls-status-header FAIL "no ready summary in the status header"
    # the pad's keys are buttons with names such as "2 ABC" and "0, or plus"
    phone_press "button:^2 ABC$" \
        && result calls-dial-pad-key PASS || result calls-dial-pad-key FAIL "the 2 key was not pressable"
    waitfor "d['callsPad'] == '2'" 6 \
        && result calls-dial-pad-fills PASS || result calls-dial-pad-fills FAIL "$(q "['callsPad']")"
    phone_press "button:^0, or plus$"
    waitfor "d['callsPad'] == '20'" 6 \
        && result calls-dial-pad-plus PASS || result calls-dial-pad-plus FAIL "$(q "['callsPad']")"
    # a contact is picked by click; typing stays only a way to find one
    ipc callsOpen 98444
    waitfor "d['callsPad'] == '98444'" 6
    timeout 20 python3 "$A11Y" find "Asha Patil" >/dev/null 2>&1 \
        && result calls-contact-suggested PASS || result calls-contact-suggested FAIL "no contact for 98444"
    phone_press "Asha Patil" \
        && result calls-contact-pickable PASS || result calls-contact-pickable FAIL "the contact was not pressable"
    waitfor "d['callsPad'] == '9844444444'" 6 \
        && result calls-contact-picks-number PASS \
        || result calls-contact-picks-number FAIL "$(q "['callsPad']")"
    timeout 20 python3 "$A11Y" find "Asha Patil" >/dev/null 2>&1 \
        && result calls-history-row PASS || result calls-history-row FAIL "the seeded call is not listed"
else
    for n in status-header dial-pad-key dial-pad-fills dial-pad-plus contact-suggested \
             contact-pickable contact-picks-number history-row; do
        result calls-$n SKIP "no accessibility client"
    done
fi
shot calls-status 0.3
shot calls-dialpad 0.3
shot calls-history 0.3

# ---- a live call: the in-call controls are drawn by the shell ----------------
# /tmp/modem-ask is the dev modem's input; one active call, then terminated.
rm -f /tmp/modem-answers
echo '{"call": {"path": "/c/calls-part", "number": "9844444444", "state": "active", "incoming": false}}' > /tmp/modem-ask
waitfor "d['modemCall'] == 'active:9844444444'" 8 \
    && result calls-in-call-shown PASS || result calls-in-call-shown FAIL "$(q "['modemCall']")"
if [ -f "$A11Y" ]; then
    for pair in "mute:Mute" "speaker:Speaker" "hangup:Hang up" "hold:Hold" "keypad:Keypad"; do
        n=${pair%%:*}; label=${pair#*:}
        timeout 20 python3 "$A11Y" find "^$label$" >/dev/null 2>&1 \
            && result calls-in-call-$n PASS || result calls-in-call-$n FAIL "no $label control"
    done
    phone_press "button:^Mute$" && sleep 0.4
    grep -q '"mute"' /tmp/modem-answers 2>/dev/null \
        && result calls-in-call-mute-recorded PASS \
        || result calls-in-call-mute-recorded FAIL "$(cat /tmp/modem-answers 2>&1)"
    phone_press "button:^Keypad$"
    timeout 20 python3 "$A11Y" find "5 JKL" >/dev/null 2>&1 \
        && result calls-in-call-dtmf-pad PASS || result calls-in-call-dtmf-pad FAIL "no keypad in the call"
else
    for n in mute speaker hangup hold keypad mute-recorded dtmf-pad; do
        result calls-in-call-$n SKIP "no accessibility client"
    done
fi
shot calls-in-call 0.3
echo '{"call": {"path": "/c/calls-part", "number": "9844444444", "state": "terminated", "incoming": false}}' > /tmp/modem-ask
waitfor "d['modemCall'] == ''" 6 \
    && result calls-in-call-ends PASS || result calls-in-call-ends FAIL "$(q "['modemCall']")"

# ---- the other three tabs, each behind its own bridge answers ----------------
if [ -f "$A11Y" ]; then
    phone_press "radio button:^Music$" \
        && result calls-music-tab PASS || result calls-music-tab FAIL "the Music tab was not pressable"
    waitfor "d['phoneMusicTitle'] == 'Mono Train' and d['phoneMusicState'] == 'Playing'" 10 \
        && result calls-music-state PASS || result calls-music-state FAIL "$(q "['phoneMusicTitle'], d['phoneMusicState']")"
    timeout 20 python3 "$A11Y" find "Mono Train" >/dev/null 2>&1 \
        && result calls-music-shown PASS || result calls-music-shown FAIL "the music tab is blank"
    phone_press "button:^Play or pause$"
    waitfor "d['phoneMusicState'] == 'Paused'" 8 \
        && result calls-music-pause PASS || result calls-music-pause FAIL "$(q "['phoneMusicState']")"
    phone_press "button:^Next$"
    waitfor "d['phoneMusicTitle'] == 'Quiet Streets'" 8 \
        && result calls-music-next PASS || result calls-music-next FAIL "$(q "['phoneMusicTitle']")"

    phone_press "radio button:^Files$" \
        && result calls-files-tab PASS || result calls-files-tab FAIL "the Files tab was not pressable"
    waitfor "d['phoneFiles'] >= 1" 10 \
        && result calls-files-listed PASS || result calls-files-listed FAIL "$(q "['phoneFiles']")"
    timeout 20 python3 "$A11Y" find "Asha-photo.jpg" >/dev/null 2>&1 \
        && result calls-files-shown PASS || result calls-files-shown FAIL "the received file is not listed"
    phone_press "switch:^Receive files from the phone$" "check box:^Receive files from the phone$"
    waitfor "d['phoneFilesReceive'] == False" 8 \
        && result calls-files-receive-switch PASS || result calls-files-receive-switch FAIL "$(q "['phoneFilesReceive']")"
    phone_press "switch:^Receive files from the phone$" "check box:^Receive files from the phone$"
    waitfor "d['phoneFilesReceive'] == True" 8 \
        && result calls-files-receive-on PASS || result calls-files-receive-on FAIL "$(q "['phoneFilesReceive']")"
    phone_press "button:^Choose a file to send$"
    waitfor "d['pickerShown']" 6
    ipc filePickerSelect /tmp/calls-send.txt; ipc filePickerAccept; sleep 0.6
    grep -q '/tmp/calls-send.txt' "$SHANI_FILES_LOG" 2>/dev/null \
        && result calls-files-send PASS || result calls-files-send FAIL "$(cat "$SHANI_FILES_LOG" 2>&1)"

    phone_press "radio button:^Remote$" \
        && result calls-remote-tab PASS || result calls-remote-tab FAIL "the Remote tab was not pressable"
    waitfor "d['phoneRemoteOn'] == True" 8 \
        && result calls-remote-on PASS || result calls-remote-on FAIL "$(q "['phoneRemoteOn']")"
    phone_press "button:^Take a photo$"
    waitfor "'shutter' in d['phoneRemoteNote']" 8 \
        && result calls-remote-key PASS || result calls-remote-key FAIL "$(q "['phoneRemoteNote']")"
    grep -q 'press shutter' "$SHANI_PHONE_REMOTE_LOG" 2>/dev/null \
        && result calls-remote-logged PASS || result calls-remote-logged FAIL "$(cat "$SHANI_PHONE_REMOTE_LOG" 2>&1)"
    # off is an empty state with one way back on
    python3 "$PHONE_TOOLS_FAKE" remote off >/dev/null
    sleep 0.5                      # let any queued status read finish first
    phone_press "radio button:^Calls$"
    phone_press "radio button:^Remote$"
    waitfor "d['phoneRemoteOn'] == False" 8 || true
    sleep 0.5
    ok=0
    for i in $(seq 1 12); do
        phone_press "button:^Turn on$" && { ok=1; break; }
        sleep 0.25
    done
    [ "$ok" = 1 ] && result calls-remote-empty-state PASS \
        || result calls-remote-empty-state FAIL "no way back on"
    waitfor "d['phoneRemoteOn'] == True" 8 \
        && result calls-remote-turn-on PASS || result calls-remote-turn-on FAIL "$(q "['phoneRemoteOn']")"
else
    for n in music-tab music-state music-shown music-pause music-next files-tab files-listed \
             files-shown files-receive-switch files-receive-on files-send remote-tab remote-on \
             remote-key remote-logged remote-empty-state remote-turn-on; do
        result calls-$n SKIP "no accessibility client"
    done
fi
shot calls-music 0.3
shot calls-files 0.3
shot calls-remote 0.3

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

export SHANI_QS_CONFIG=/work/shani   # `shani app` speaks to the dev session's shell
# a number on a web page: tel: and sms: links open the shell's own Calls and
# Messages with the number in (the desktop entry's %u) - nothing is dialled
ipc closeAll
python3 /work/bin/shani app calls "tel:+91-98200%2012345;ext=1" >/dev/null 2>&1
waitfor "d['callsShown'] and d['callsPad'] == '+91-98200 12345'" 6 && result calls-tel-link-fills-the-pad PASS \
    || result calls-tel-link-fills-the-pad FAIL "$(q "['callsShown'], d['callsPad']")"
python3 /work/bin/shani app messages "sms:+919876543210?body=hi" >/dev/null 2>&1
waitfor "d['messagesPending'] == '+919876543210'" 6 && result messages-sms-link-fills-the-number PASS \
    || result messages-sms-link-fills-the-number FAIL "$(q "['messagesPending']")"
ipc closeAll
