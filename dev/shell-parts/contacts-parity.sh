# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=contacts-parity)
# ---- Contacts parity: the phone's book as a second source, "Save here", choosing
#      several cards for one export/delete, and the rest of the editor's fields.
#      The phone side is the image's own Android stand-in (SHANI_ADB from
#      session.sh); nothing here touches a real phone or the person's display.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/shani-shell"
CONTACTS="$DATA_HOME/contacts"
EXPORT=/tmp/contacts-parity-export.vcf
SNAP=/tmp/contacts-parity-before
mkdir -p "$CONTACTS"
(cd "$CONTACTS" && ls *.vcf 2>/dev/null) > "$SNAP" || : > "$SNAP"
HAD_SAVED=0
[ -e "$HOME/contacts.vcf" ] && HAD_SAVED=1

# session.sh has no SHANI_CONTACTS_TOOL yet, so the running shell points at the
# installed bridge path, which the dev image does not have. Restart it with the
# checkout's bridge (the same override the other bridges get from session.sh).
qpid=$(pgrep -o -x qs)
[ -n "$qpid" ] && stopshell "$qpid"
export SHANI_CONTACTS_TOOL=/work/bridge/contacts.py
QT_LOGGING_RULES="qt.scenegraph.time.renderloop=true" qs -p /work/shani >>/work/out/logs/qs.log 2>&1 &
retry 30 st >/dev/null 2>&1
waitfor "d.get('settingsLoaded') == True" 15 || true

phone_press() {
    for label in "$@"; do
        timeout 20 python3 "$A11Y" press "$label" >/dev/null 2>&1 && return 0
    done
    return 1
}
a11y_wait() {
    _n=0
    while [ $_n -lt 40 ]; do
        timeout 6 python3 "$A11Y" find "$1" >/dev/null 2>&1 && return 0
        sleep 0.25; _n=$((_n + 1))
    done
    return 1
}
press_wait() {
    _n=0
    while [ $_n -lt 20 ]; do
        phone_press "$1" && return 0
        sleep 0.25; _n=$((_n + 1))
    done
    return 1
}
has_card() { grep -l "FN:$1" "$CONTACTS"/*.vcf >/dev/null 2>&1; }

# cards with unique uids: the full suite sources every part in one session
for pair in "parity-ada:Ada Parity:+15550111" \
            "parity-bob:Bob Parity:+15550112" \
            "parity-field:Field Parity:+15550113"; do
    uid=${pair%%:*}; rest=${pair#*:}; name=${rest%%:*}; number=${rest##*:}
    cat > "$CONTACTS/$uid.vcf" <<VCF
BEGIN:VCARD
VERSION:4.0
UID:urn:uuid:$uid
FN:$name
N:Parity;$name;;;
TEL;TYPE=cell:$number
END:VCARD
VCF
done

# ---- the window and the two sources -------------------------------------------
ipc contactsOpen
waitfor "d['contactsShown'] == True" 8 && result contacts-parity-opens PASS \
    || result contacts-parity-opens FAIL "$(q "['contactsShown']")"
a11y_wait "Ada Parity" \
    && result contacts-parity-local-rows PASS \
    || result contacts-parity-local-rows FAIL "the seeded cards are not listed"
shot contacts-parity-list 0.4

before=$(q "['contactsCount']")
press_wait "radio button:^Show contacts from the phone$" \
    && result contacts-parity-source-chip PASS \
    || result contacts-parity-source-chip FAIL "the phone chip was not pressable"
a11y_wait "Alice Smith" \
    && result contacts-parity-phone-source PASS \
    || result contacts-parity-phone-source FAIL "$(python3 /work/bridge/contacts.py phone 2>&1)"
shot contacts-parity-phone 0.4

# ---- a phone contact is a copy here, never an overwrite of the phone book -----
SAVE_HERE="button:^Save this phone contact to my contacts$"
press_wait "Alice Smith" && a11y_wait "$SAVE_HERE" \
    && result contacts-parity-phone-detail PASS \
    || result contacts-parity-phone-detail FAIL "no detail sheet for the phone contact"
shot contacts-parity-detail 0.3
press_wait "$SAVE_HERE" \
    && result contacts-parity-save-here-button PASS \
    || result contacts-parity-save-here-button FAIL "Save here was not pressable"
waitfor "d['contactsCount'] > $before" 10 \
    && result contacts-parity-saved-here PASS "$(q "['contactsCount']")" \
    || result contacts-parity-saved-here FAIL "$(q "['contactsCount']")"
has_card "Alice Smith" \
    && result contacts-parity-saved-card PASS \
    || result contacts-parity-saved-card FAIL "no local vCard named Alice Smith"

# ---- several cards, one export, one confirmed delete --------------------------
press_wait "radio button:^Show my contacts$"
press_wait "button:^Select several contacts$" \
    && result contacts-parity-select-mode PASS \
    || result contacts-parity-select-mode FAIL "the Select button was not pressable"
a11y_wait "check box:^Select Ada Parity$" \
    && result contacts-parity-checkbox PASS \
    || result contacts-parity-checkbox FAIL "no checkbox in the row"
press_wait "Ada Parity" && press_wait "Bob Parity"
a11y_wait "2 chosen" \
    && result contacts-parity-two-chosen PASS \
    || result contacts-parity-two-chosen FAIL "the selection count is not shown"
shot contacts-parity-select 0.4

rm -f "$EXPORT"
press_wait "button:^Export the chosen contacts$"
waitfor "d['pickerShown'] == True" 6
# a Save picker keeps the suggested name in the folder it opened in
ipc filePickerAccept
sleep 1
saved="$HOME/contacts.vcf"
[ -s "$saved" ] && cp "$saved" "$EXPORT"
[ -s "$EXPORT" ] && grep -q 'FN:Ada Parity' "$EXPORT" && grep -q 'FN:Bob Parity' "$EXPORT" \
    && [ "$(grep -c 'BEGIN:VCARD' "$EXPORT")" = 2 ] \
    && result contacts-parity-export-chosen PASS \
    || result contacts-parity-export-chosen FAIL "$(head -c 120 "$saved" 2>&1)"

after_save=$(q "['contactsCount']")
# ConfirmButton keeps its accessible name when armed: press the same control twice
DEL="button:^Delete chosen contacts$"
press_wait "$DEL" && a11y_wait "$DEL" \
    && result contacts-parity-delete-arms PASS \
    || result contacts-parity-delete-arms FAIL "the delete button was not pressable"
press_wait "$DEL"
waitfor "d['contactsCount'] == $((after_save - 2))" 10 \
    && result contacts-parity-delete-chosen PASS "$(q "['contactsCount']")" \
    || result contacts-parity-delete-chosen FAIL "$(q "['contactsCount']")"
! has_card "Ada Parity" && ! has_card "Bob Parity" && has_card "Alice Smith" \
    && result contacts-parity-delete-only-chosen PASS \
    || result contacts-parity-delete-only-chosen FAIL "the wrong cards were deleted"

# ---- the rest of the editor's fields are written into the card ----------------
press_wait "Field Parity" && press_wait "button:^Edit$"
a11y_wait "text:^Birthday$" \
    && result contacts-parity-editor-fields PASS \
    || result contacts-parity-editor-fields FAIL "the extra editor fields are missing"
shot contacts-parity-editor 0.4
press_wait "text:^Birthday$"
wtype "1990-01-31"
press_wait "button:^Save changes$"
sleep 1
card=$(grep -l 'FN:Field Parity' "$CONTACTS"/*.vcf 2>/dev/null | head -1)
[ -n "$card" ] && grep -q 'BDAY:1990-01-31' "$card" \
    && result contacts-parity-birthday-saved PASS \
    || result contacts-parity-birthday-saved FAIL "$(cat "$card" 2>&1)"

# ---- leave the session as it was found ----------------------------------------
ipc closeAll
for f in "$CONTACTS"/*.vcf; do
    [ -e "$f" ] || continue
    grep -qx "$(basename "$f")" "$SNAP" || rm -f "$f"
done
rm -f "$SNAP" "$EXPORT"
[ "$HAD_SAVED" = 0 ] && rm -f "$HOME/contacts.vcf"
