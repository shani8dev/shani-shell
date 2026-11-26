# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=devices)
# ---- Devices: the native window against stand-ins only. The handset comes from
#      dev/fake-adb-full.py ($SHANI_ADB), nearby Bluetooth from
#      dev/fake-phone-devices.py ($SHANI_BTCTL), NFC/IR from the two tiny stand-ins
#      below and the SIP line from a local accounts file. No hardware, no root.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
ADB=${SHANI_ADB:-/work/dev/fake-adb-full.py}
BT=${SHANI_BTCTL:-/work/dev/fake-phone-devices.py}
NFC=/work/dev/fake-nfc.py
IR=/work/dev/fake-ir.py
FM=/work/dev/fake-fm.py
ADB_LOG=${SHANI_ADB_LOG:-/tmp/fake-adb-calls}
BT_LOG=${SHANI_BTCTL_LOG:-/tmp/fake-bt-calls}
SERIAL=0A1B2C3D
# these apply to bridge calls made here; the parent wires them in session.sh for
# the shell's own bridge processes.
export SHANI_NFC="$NFC" SHANI_IR="$IR" SHANI_FM="$FM"

rm -f "$ADB_LOG" "$BT_LOG"
python3 "$BT" pair 0C:52:34:9A:1B:2C >/dev/null 2>&1

# one local SIP account, so Settings > Phone has a landline-style line to show
python3 - <<'PY'
import json, os
p = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
                 "shani-shell", "sip-accounts.json")
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump({"accounts": [{"id": "devtest01", "name": "Test line",
                         "username": "devtest01", "password": "offline",
                         "domain": "example.invalid", "port": 5060,
                         "transport": "udp", "enabled": False, "register": False}]},
          open(p, "w"))
PY

# The bridge must reach each stand-in. Calling devices.py with the override set
# here checks the wiring even before session.sh points the global env at them.
bridge_android() {
    SHANI_ADB="$ADB" SHANI_ADB_LOG="$ADB_LOG" \
        python3 /work/bridge/devices.py android "$@" 2>/dev/null
}
bridge_android info "$SERIAL" | grep -q 'Pixel 7' \
    && result devices-bridge-finds-phone PASS \
    || result devices-bridge-finds-phone FAIL "$(bridge_android info "$SERIAL")"
bridge_android battery "$SERIAL" | grep -q 'level: 76' \
    && result devices-bridge-battery PASS || result devices-bridge-battery FAIL "$(bridge_android battery "$SERIAL")"
bridge_android storage "$SERIAL" | grep -q '50G' \
    && result devices-bridge-storage PASS || result devices-bridge-storage FAIL "$(bridge_android storage "$SERIAL")"
# compare the first eight bytes themselves: od's spacing differs across images
"$ADB" exec-out screencap -p 2>/dev/null \
    | python3 -c 'import sys; sys.exit(0 if sys.stdin.buffer.read(8) == b"\x89PNG\r\n\x1a\n" else 1)' \
    && result devices-fake-screenshot-png PASS || result devices-fake-screenshot-png FAIL "not a PNG"
SHANI_NFC="$NFC" python3 /work/bridge/devices.py nfc read 2>/dev/null | grep -q 'Asha Patil' \
    && result devices-bridge-nfc PASS \
    || result devices-bridge-nfc FAIL "$(SHANI_NFC="$NFC" python3 /work/bridge/devices.py nfc read 2>&1)"
SHANI_IR="$IR" python3 /work/bridge/devices.py ir list 2>/dev/null | grep -q 'tv' \
    && result devices-bridge-ir PASS \
    || result devices-bridge-ir FAIL "$(SHANI_IR="$IR" python3 /work/bridge/devices.py ir list 2>&1)"
SHANI_FM="$FM" python3 /work/bridge/devices.py fm state 2>/dev/null | grep -q '"state"' \
    && result devices-bridge-fm PASS \
    || result devices-bridge-fm FAIL "$(SHANI_FM="$FM" python3 /work/bridge/devices.py fm state 2>&1)"
rm -f "$ADB_LOG"                 # discard the smoke calls above, keep the flow's

# the bridge answers asynchronously; wait for the stand-in's log, not the click
waitgrep() {
    pattern=$1; i=0
    until grep -Eq "$pattern" "$ADB_LOG" 2>/dev/null || [ "$i" -ge 24 ]; do
        sleep 0.25; i=$((i + 1))
    done
    grep -Eq "$pattern" "$ADB_LOG" 2>/dev/null
}

# press a control by any of the names the window may give it
press() {
    for label in "$@"; do
        timeout 12 python3 "$A11Y" press "$label" >/dev/null 2>&1 && return 0
    done
    return 1
}

# ---- open the window and list the phone ---------------------------------------
ipc devicesOpen
waitfor "d['devicesShown'] == True" 8 && result devices-opens PASS \
    || result devices-opens FAIL "$(q "['devicesShown']")"
shot devices-window 0.4
waitfor "d['devicesCount'] >= 1" 10 && result devices-lists-paired-phone PASS \
    || result devices-lists-paired-phone FAIL "$(q "['devicesCount'], d['devicesNote']")"

# ---- the Android phone's actions ----------------------------------------------
if [ -f "$A11Y" ]; then
    press "radio button:^Android phone$" \
        && result devices-android-tab PASS || result devices-android-tab FAIL "the Android tab was not pressable"
    press "radio button:^Pixel 7$" "radio button:^0A1B2C3D$"
    timeout 20 python3 "$A11Y" find "Pixel 7" >/dev/null 2>&1 \
        && result devices-android-phone-shown PASS \
        || result devices-android-phone-shown FAIL "the phone was not listed"
    press "button:^Read battery$"
    press "button:^Read storage$"
    shot devices-android-info 0.3

    press "button:^Take a screenshot$" \
        && result devices-screenshot-button PASS || result devices-screenshot-button FAIL "no screenshot button"
    waitgrep 'exec-out screencap -p' \
        && result devices-screenshot-calls-adb PASS || result devices-screenshot-calls-adb FAIL "$(cat "$ADB_LOG" 2>&1)"
    waitfor "'Screenshot' in d['devicesNote']" 8 && result devices-screenshot-note PASS \
        || result devices-screenshot-note FAIL "$(q "['devicesNote']")"

    press "button:^Record the screen$" \
        && result devices-record-button PASS || result devices-record-button FAIL "no record button"
    waitgrep 'screenrecord' \
        && result devices-record-calls-adb PASS || result devices-record-calls-adb FAIL "$(cat "$ADB_LOG" 2>&1)"
    waitfor "'Recording' in d['devicesNote']" 10 && result devices-record-note PASS \
        || result devices-record-note FAIL "$(q "['devicesNote']")"

    # a link is a typed custom value; the button stays off until one is there
    press "text:^Web address to open on the phone$" "text:^Web address$"
    wtype "https://example.invalid"
    press "button:^Open link$" \
        && result devices-open-link-button PASS || result devices-open-link-button FAIL "no open-link button"
    waitgrep 'shell am start' \
        && result devices-open-link-calls-adb PASS || result devices-open-link-calls-adb FAIL "$(cat "$ADB_LOG" 2>&1)"

    press "button:^Open app$" \
        && result devices-open-app-button PASS || result devices-open-app-button FAIL "no open-app button"
    # the app field needs a name too; the hint field is optional in the window
    press "text:^App name or id, if it is not listed$" "text:^App name or id$"
    wtype "com.example.notes"
    press "button:^Open app$"
    waitgrep 'shell (monkey|am start)' \
        && result devices-open-app-calls-adb PASS || result devices-open-app-calls-adb FAIL "$(cat "$ADB_LOG" 2>&1)"

    # a file is chosen through the shell's picker, then sent with one click
    printf 'a small file\n' > /tmp/devices-send.txt
    ipc filePickerOpen open /tmp
    waitfor "d['pickerShown']" 6
    ipc filePickerSelect /tmp/devices-send.txt; ipc filePickerAccept; sleep 0.6
    press "button:^Send$" \
        && result devices-send-file-button PASS || result devices-send-file-button FAIL "no send button"
    waitgrep 'push ' \
        && result devices-send-file-calls-adb PASS || result devices-send-file-calls-adb FAIL "$(cat "$ADB_LOG" 2>&1)"
else
    for n in android-tab android-phone-shown screenshot-button screenshot-calls-adb screenshot-note \
             record-button record-calls-adb record-note open-link-button open-link-calls-adb \
             open-app-button open-app-calls-adb send-file-button send-file-calls-adb; do
        result devices-$n SKIP "no accessibility client"
    done
    ipc closeAll
fi

# ---- connect a phone (the nearby device is paired by the stand-in) -------------
if [ -f "$A11Y" ]; then
    press "radio button:^Phones$"
    press "button:^Connect$" \
        && result devices-connect-button PASS || result devices-connect-button FAIL "no Connect button"
    before=$(q "['devicesCount']")
    press "radio button:^Bluetooth device$"
    press "text field:^Address or code, if needed$" "text field:^Address or code$"
    wtype "0C:52:34:9A:1B:2C"
    press "button:^Connect$"
    waitfor "d['devicesCount'] >= $before" 8 && result devices-connect-adds PASS \
        || result devices-connect-adds FAIL "$(q "['devicesCount']") (was $before)"
    grep -q '0C:52:34:9A:1B:2C' "$BT_LOG" 2>/dev/null \
        && result devices-connect-asked-bluetooth PASS \
        || result devices-connect-asked-bluetooth FAIL "$(cat "$BT_LOG" 2>&1)"
else
    result devices-connect-button SKIP "no accessibility client"
    result devices-connect-adds SKIP "no accessibility client"
    result devices-connect-asked-bluetooth SKIP "no accessibility client"
fi

# ---- this screen on the phone: window/screen and touch/typing switches ---------
if [ -f "$A11Y" ]; then
    press "radio button:^This screen$" \
        && result devices-screen-tab PASS || result devices-screen-tab FAIL "the screen tab was not pressable"
    press "radio button:^One window$" "radio button:^Window$"
    press "switch:^Allow touches$" "check box:^Allow touches$"
    press "switch:^Allow typing$" "check box:^Allow typing$"
    press "button:^Start sharing$" \
        && result devices-sharing-button PASS || result devices-sharing-button FAIL "no Start sharing button"
    waitfor "d['screenState'] in ('running', 'on')" 10 && result devices-screen-state PASS \
        || result devices-screen-state FAIL "$(q "['screenState']")"
    press "radio button:^The whole screen$" "radio button:^Whole screen$"
    waitfor "d['screenState'] in ('running', 'on')" 6 && result devices-screen-whole PASS \
        || result devices-screen-whole FAIL "$(q "['screenState']")"
    shot devices-screen 0.4
    press "button:^Stop sharing$"; sleep 1
else
    for n in screen-tab sharing-button screen-state screen-whole; do
        result devices-$n SKIP "no accessibility client"
    done
fi

# ---- FM radio: a source on Media Player > Radio --------------------------------
if [ -f "$A11Y" ]; then
    ipc radioShow popular; sleep 1
    press "radio button:^FM radio$" \
        && result devices-fm-is-a-radio-source PASS \
        || result devices-fm-is-a-radio-source FAIL "Media Player has no FM source"
    timeout 20 python3 "$A11Y" find "FM radio" >/dev/null 2>&1 \
        && result devices-fm-source-drawn PASS || result devices-fm-source-drawn FAIL "the FM pane is blank"
    # a custom frequency is typed; 98.5 is what the stand-in will report
    press "text field:^For example 91.1$" "text field:^Frequency in MHz$"
    wtype "98.5"
    press "button:^Start$" "button:^Start radio$"
    waitfor "d['fmState'] in ('running', 'on') and abs(d['fmFrequency'] - 98.5) < 0.01" 10 \
        && result devices-fm-state PASS \
        || result devices-fm-state FAIL "$(q "['fmState'], d['fmFrequency']")"
    shot devices-fm 0.3
    press "button:^Stop$" "button:^Stop radio$"
    ipc mediaClose
else
    result devices-fm-is-a-radio-source SKIP "no accessibility client"
    result devices-fm-source-drawn SKIP "no accessibility client"
    result devices-fm-state SKIP "no accessibility client"
fi

# ---- NFC read, IR list and send ------------------------------------------------
if [ -f "$A11Y" ]; then
    ipc devicesOpen; sleep 0.5
    press "radio button:^Gadgets$" \
        && result devices-gadgets-tab PASS || result devices-gadgets-tab FAIL "the gadgets tab was not pressable"
    press "button:^Read a tag$" "button:^Read NFC$"
    waitfor "d['nfcText'] != ''" 10 && result devices-nfc-read PASS \
        || result devices-nfc-read FAIL "$(q "['nfcText'], d['devicesNote']")"
    press "button:^Look for codes$"
    waitfor "d['irCodes'] != ''" 10 && result devices-ir-lists PASS \
        || result devices-ir-lists FAIL "$(q "['irCodes']")"
    press "radio button:^power$" "radio button:^on$"
    press "button:^Send code$" "button:^Send IR$" \
        && result devices-ir-send-button PASS || result devices-ir-send-button FAIL "no Send code button"
    waitfor "'Code sent' in d['devicesNote']" 8 \
        && result devices-ir-send PASS || result devices-ir-send FAIL "$(q "['devicesNote']")"
    shot devices-gadgets 0.3
else
    for n in gadgets-tab nfc-read ir-lists ir-send-button ir-send; do
        result devices-$n SKIP "no accessibility client"
    done
fi

ipc devicesClose
waitfor "d['devicesShown'] == False" 6 && result devices-closes PASS \
    || result devices-closes FAIL "$(q "['devicesShown']")"

# ---- the lines are also in Settings > Phone (Search must find the page) --------
ipc settingsCategory phone
waitfor "d['settingsOpen'] and d['settingsCat'] == 'phone'" 8 \
    && result devices-phone-settings-opens PASS \
    || result devices-phone-settings-opens FAIL "$(q "['settingsOpen'], d['settingsCat']")"
waitfor "'sip-devtest01' in str(d['lines']) and 'Test line' in str(d['sipAccounts'])" 10 \
    && result devices-sip-in-settings PASS \
    || result devices-sip-in-settings FAIL "$(q "['lines'], d['sipAccounts']")"
ipc closeAll
