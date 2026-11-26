# sourced by dev/shell-test.sh (alone: sh dev/check.sh shell=phone-parity)
# ---- Calls/Messages parity: history row actions, Clear all + Undo, and the
#      new-message contact picker. A11Y presses the real controls; the proof is
#      the shell's own state (callsCount, messagesPending) and the files the
#      bridge writes. No service-activation checks here: calls.sh owns those.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/shani-shell"
CALLS_FILE="$DATA_HOME/calls.json"
CALLS_BACKUP=/tmp/phone-parity-calls.json
CONTACTS="$DATA_HOME/contacts"
UNDO="${XDG_STATE_HOME:-$HOME/.local/state}/shani-shell/call-undo.json"

phone_press() {
    for label in "$@"; do
        timeout 20 python3 "$A11Y" press "$label" >/dev/null 2>&1 && return 0
    done
    return 1
}
phone_find() {
    timeout 20 python3 "$A11Y" find "$1" >/dev/null 2>&1
}

# Keep the state of the other parts exactly as we found it.
rm -f "$CALLS_BACKUP" "$CALLS_BACKUP.none"
if [ -f "$CALLS_FILE" ]; then cp "$CALLS_FILE" "$CALLS_BACKUP"; else : > "$CALLS_BACKUP.none"; fi
mkdir -p "$DATA_HOME" "$CONTACTS"
find "$CONTACTS" -maxdepth 1 -name '*.vcf' -printf '%f\n' 2>/dev/null | sort > /tmp/phone-parity-contacts-before
rm -f "$UNDO"

python3 - "$CALLS_FILE" <<'PY'
import json, sys, time
now = int(time.time())
rows = [
    {"id": "parity-c1", "line": "phone", "number": "9844444444", "name": "Asha Patil",
     "direction": "in", "missed": False, "when": now + 3, "seconds": 42},
    {"id": "parity-c2", "line": "phone", "number": "9911111111", "name": "Ravi Shah",
     "direction": "out", "missed": False, "when": now + 2, "seconds": 95},
    {"id": "parity-c3", "line": "landline", "number": "9666666666", "name": "Meera Iyer",
     "direction": "in", "missed": True, "when": now + 1, "seconds": 0},
]
json.dump(rows, open(sys.argv[1], "w"))
PY
# one saved contact, so the picker has a chip to press; Ravi is deliberately not here
cat > "$CONTACTS/phone-parity-asha.vcf" <<'VCF'
BEGIN:VCARD
VERSION:4.0
UID:urn:uuid:phone-parity-asha
FN:Asha Patil
N:Patil;Asha;;;
TEL;TYPE=CELL:9844444444
END:VCF
VCF

# ---- open Calls, read the seeded history ------------------------------------
ipc callsOpen ""
waitfor "d['callsShown'] == True and d['callsCount'] == 3" 10 \
    && result phone-parity-history-shown PASS \
    || result phone-parity-history-shown FAIL "$(q "['callsShown'], d['callsCount']")"

if [ -f "$A11Y" ]; then
    for name in "Send a message" "Save as a contact" "Delete call" "Clear all call history"; do
        phone_find "button:^$name\$" \
            && result "phone-parity-$name-present" PASS \
            || result "phone-parity-$name-present" FAIL "no button named $name"
    done

    # ---- a row's "Send a message" opens the composer on that number ----------
    # this action closes Calls while AT-SPI is reading the tree, so the client
    # can exit non-zero after it fired; the shell's state is the proof
    phone_press "button:^Send a message\$" || true
    waitfor "d['messagesShown'] == True and d['messagesPending'] == '9844444444'" 10 \
        && result phone-parity-message-pick PASS \
        || result phone-parity-message-pick FAIL "$(q "['messagesShown'], d['messagesPending']")"
    ipc messagesClose
    ipc callsOpen ""
    waitfor "d['callsShown'] == True and d['callsCount'] == 3" 8 || true

    # ---- a row's "Save as a contact" writes a vCard (the second row) ----------
    timeout 20 python3 "$A11Y" press "button:^Save as a contact\$" 2 >/dev/null 2>&1 \
        && result phone-parity-save-press PASS \
        || result phone-parity-save-press FAIL "the save action was not pressable"
    sleep 0.6
    grep -rl '9911111111' "$CONTACTS" >/dev/null 2>&1 \
        && result phone-parity-save-writes-contact PASS \
        || result phone-parity-save-writes-contact FAIL "no contact for the saved number"
    shot phone-parity-history 0.3

    # ---- Clear all, then Undo puts the rows back -------------------------------
    phone_press "button:^Clear all call history\$"
    sleep 0.3
    phone_press "button:^Clear all call history\$" \
        && result phone-parity-clear-press PASS \
        || result phone-parity-clear-press FAIL "Clear all was not pressable"
    waitfor "d['callsCount'] == 0" 10 \
        && result phone-parity-clears-history PASS \
        || result phone-parity-clears-history FAIL "$(q "['callsCount']")"
    phone_press "button:^Undo clear\$" \
        && result phone-parity-undo-press PASS \
        || result phone-parity-undo-press FAIL "Undo was not pressable"
    waitfor "d['callsCount'] == 3" 10 \
        && result phone-parity-undo-restores PASS \
        || result phone-parity-undo-restores FAIL "$(q "['callsCount']")"
    # a second Undo is not offered after the token was used
    if phone_find "button:^Undo clear\$"; then
        result phone-parity-undo-once FAIL "Undo is still offered"
    else
        result phone-parity-undo-once PASS
    fi

    # ---- Delete one row: destructive, two taps --------------------------------
    phone_press "button:^Delete call\$"
    sleep 0.3
    phone_press "button:^Delete call\$" \
        && result phone-parity-delete-press PASS \
        || result phone-parity-delete-press FAIL "Delete was not pressable"
    waitfor "d['callsCount'] == 2" 10 \
        && result phone-parity-deletes-row PASS \
        || result phone-parity-deletes-row FAIL "$(q "['callsCount']")"
else
    for name in message-pick save-press save-writes-contact \
                clear-press clears-history undo-press undo-restores undo-once \
                delete-press deletes-row; do
        result "phone-parity-$name" SKIP "no accessibility client"
    done
fi

# ---- a new message: pick a contact by click, typing is optional -------------
ipc callsClose
ipc messagesOpen ""
waitfor "d['messagesShown'] == True" 8 || true
if [ -f "$A11Y" ]; then
    phone_press "button:^New message\$" \
        && result phone-parity-new-message-press PASS \
        || result phone-parity-new-message-press FAIL "New message was not pressable"
    phone_press "radio button:^Asha Patil · 9844444444\$" \
        && result phone-parity-contact-pick PASS \
        || result phone-parity-contact-pick FAIL "the contact chip was not pressable"
    phone_find "Message to 9844444444" \
        && result phone-parity-composer-addressed PASS \
        || result phone-parity-composer-addressed FAIL "the composer is not addressed to the contact"
    shot phone-parity-picker 0.3
else
    for name in new-message-press contact-pick composer-addressed; do
        result "phone-parity-$name" SKIP "no accessibility client"
    done
fi

ipc closeAll
ipc callsClose
ipc messagesClose

# leave both stores as they were found, for the other parts in one session
find "$CONTACTS" -maxdepth 1 -name '*.vcf' -printf '%f\n' 2>/dev/null | sort > /tmp/phone-parity-contacts-after
for f in $(comm -13 /tmp/phone-parity-contacts-before /tmp/phone-parity-contacts-after); do
    rm -f "$CONTACTS/$f"
done
rm -f /tmp/phone-parity-contacts-before /tmp/phone-parity-contacts-after "$UNDO"
if [ -f "$CALLS_BACKUP.none" ]; then
    rm -f "$CALLS_FILE" "$CALLS_BACKUP.none"
else
    cp "$CALLS_BACKUP" "$CALLS_FILE"
fi
rm -f "$CALLS_BACKUP"
