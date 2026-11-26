# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=encryption)
# ---- Settings > Security > Encryption and boot: gen-efi's stand-in answers the
#      same JSON as the real tool. The page is opened in three states, each one
#      screenshotted; then the four actions and the Secure Boot key steps are
#      run through the bridge and checked against the stand-in's call log.
#      No passphrase, PIN or recovery key is ever written to a log.
FS=${FAKE_GEN_EFI_DIR:-/tmp/fake-gen-efi}; mkdir -p "$FS"
TOOL=/work/bridge/system_security_boot.py
A11Y=${A11Y:-/testbed/lib/a11y_client.py}

state() { printf '%s' "$1" > "$FS/state"; : > "$FS/calls"; }
# leaving the category first unloads its Loader, so the next open is a fresh page
open() { ipc settingsCategory personal; sleep 0.4; ipc settingsCategory security; sleep 0.8; }
# the page asks for nothing on open (every gen-efi call is a password prompt);
# the state comes when the person presses Read state
readstate() { timeout 20 python3 "$A11Y" press "button:^Read state$" >/dev/null 2>&1; }

# ---- the page in three states ------------------------------------------------
state encrypted-tpm
open
[ ! -s "$FS/calls" ] && result encryption-no-prompt-on-open PASS \
    || result encryption-no-prompt-on-open FAIL "opening the page ran: $(head -c 120 "$FS/calls")"
readstate
waitfor "d.get('systemState',{}).get('encryptionBoot',{}).get('loaded') is True and d['systemState']['encryptionBoot'].get('tpmEnrolled') is True" 12 \
    && result encryption-tpm-page PASS || result encryption-tpm-page FAIL "$(q "['systemState'].get('encryptionBoot')")"
shot encryption-tpm 0.8
state encrypted-no-tpm
open
readstate
waitfor "d.get('systemState',{}).get('encryptionBoot',{}).get('loaded') is True and d['systemState']['encryptionBoot'].get('encrypted') is True and d['systemState']['encryptionBoot'].get('tpmPresent') is False" 12 \
    && result encryption-no-tpm-page PASS || result encryption-no-tpm-page FAIL "$(q "['systemState'].get('encryptionBoot')")"
shot encryption-no-tpm 0.8

state plain
open
readstate
waitfor "d.get('systemState',{}).get('encryptionBoot',{}).get('loaded') is True and d['systemState']['encryptionBoot'].get('encrypted') is False" 12 \
    && result encryption-plain-page PASS || result encryption-plain-page FAIL "$(q "['systemState'].get('encryptionBoot')")"
shot encryption-plain 0.8

# every action must be reachable by name, not only by a pointer position
if [ -f "$A11Y" ]; then
    tree=$(timeout 20 python3 "$A11Y" tree --max-depth 16 2>/dev/null)
    missing=""
    for name in "Make a recovery key" "Save a copy of the disk header" "Stage a new signing key"; do
        printf '%s' "$tree" | grep -qF "$name" || missing="$missing $name"
    done
    [ -z "$missing" ] && result encryption-actions-named PASS \
        || result encryption-actions-named FAIL "missing:$missing"
else
    result encryption-actions-named SKIP "no AT-SPI"
fi

# ---- the actions, through the bridge and the stand-in ------------------------
state encrypted-tpm
out=$(printf 'a good passphrase\n' | python3 "$TOOL" enroll 2>/dev/null)
echo "$out" | grep -q '"ok": true' && grep -q 'enroll-tpm2 --stdin' "$FS/calls" \
    && result encryption-enroll PASS || result encryption-enroll FAIL "$out"
grep -q 'a good passphrase' "$FS/calls" && result encryption-secret-not-logged FAIL "passphrase in call log" \
    || result encryption-secret-not-logged PASS

out=$(printf 'a good passphrase\n123456\n' | python3 "$TOOL" enroll 2>/dev/null)
echo "$out" | grep -q '"ok": true' && grep -q -- '--with-pin' "$FS/calls" \
    && grep -q 'encrypted-tpm-pin' "$FS/state" \
    && result encryption-enroll-pin PASS || result encryption-enroll-pin FAIL "$out"

out=$(python3 "$TOOL" remove 2>/dev/null)
echo "$out" | grep -q '"ok": true' && grep -q 'remove-tpm2' "$FS/calls" \
    && grep -q 'encrypted-no-tpm' "$FS/state" \
    && result encryption-remove PASS || result encryption-remove FAIL "$out"

state encrypted-tpm
out=$(printf 'a good passphrase\n' | python3 "$TOOL" recovery-key 2>/dev/null)
key=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))' 2>/dev/null)
printf '%s' "$key" | grep -qE '^[cbdefghijklnrtuv]{8}(-[cbdefghijklnrtuv]{8}){7}$' \
    && grep -q 'recovery-key --stdin' "$FS/calls" \
    && result encryption-recovery-key PASS || result encryption-recovery-key FAIL "$out"
# shown once: the key is nowhere on disk, and never in the bridge's own log
if [ -n "$key" ]; then
    grep -R -q -F -- "$key" /work/out/logs "$FS" 2>/dev/null \
        && result encryption-key-not-logged FAIL "recovery key in a log" \
        || result encryption-key-not-logged PASS
else
    result encryption-key-not-logged FAIL "no key to check"
fi

out=$(python3 "$TOOL" header-backup "$FS/header.img" 2>/dev/null)
echo "$out" | grep -q '"ok": true' && [ -f "$FS/header.img" ] \
    && [ "$(head -c 4 "$FS/header.img" | od -An -tx1 | tr -d ' \n')" = "4c554b53" ] \
    && [ "$(stat -c %a "$FS/header.img")" = 600 ] \
    && result encryption-header-backup PASS || result encryption-header-backup FAIL "$out"

for step in enroll-mok cleanup-mok; do
    out=$(python3 "$TOOL" "$step" 2>/dev/null)
    echo "$out" | grep -q '"ok": true' && grep -q "$step" "$FS/calls" \
        && result "encryption-$step" PASS || result "encryption-$step" FAIL "$out"
done

# the page follows the stand-in after the actions
state encrypted-tpm-pin
open
readstate
waitfor "d.get('systemState',{}).get('encryptionBoot',{}).get('loaded') is True and d['systemState']['encryptionBoot'].get('tpmPin') is True" 12 \
    && result encryption-after-actions PASS || result encryption-after-actions FAIL "$(q "['systemState'].get('encryptionBoot')")"
shot encryption-after-actions 0.8

ipc closeAll
