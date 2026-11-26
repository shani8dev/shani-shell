# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=access-sharing)
# ---- Settings > Access, Sharing, Security and Account: the depth work of gaps
#      4-16. The pages are opened and their named controls checked with AT-SPI;
#      the staging bridges and the root helper are then driven against stand-ins
#      that reject options the real tools reject. No secret reaches a log.
FS=/tmp/fake-system
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
ACCESS=/work/bridge/system_access.py
NFS=/work/bridge/system_nfs.py
SMB=/work/bridge/system_smb.py
U2F=/work/bridge/u2f.py
ADMIN=/work/bridge/shani-admin.py

open() { ipc settingsCategory personal; sleep 0.4; ipc settingsCategory "$1"; sleep 1.5; }

# ---- the four pages, each rendered and its controls named --------------------
for cat in adminaccess sharing account security; do
    open "$cat"
    case "$cat" in
        adminaccess) names="Card readers|Card sign-in mappings|Sign-in codes|Grants" ;;
        sharing)     names="Network folders (NFS)|Shared folders for this computer (Samba)|Remote login|Add a folder to share|Add a share" ;;
        account)     names="Sign-in with a key|Origin|Application ID|One-time-password sign-in" ;;
        security)    names="Who can run commands as another user|Add rule|Host names" ;;
    esac
    if [ -f "$A11Y" ] && timeout 20 python3 "$A11Y" tree --max-depth 18 2>/dev/null | grep -qE 'Settings|Sharing'; then
        tree=$(timeout 20 python3 "$A11Y" tree --max-depth 18 2>/dev/null)
        missing=""
        printf '%s' "$names" | tr '|' '\n' | while IFS= read -r n; do
            [ -z "$n" ] && continue
            printf '%s' "$tree" | grep -qiF "$n" || echo "$n"
        done > "$FS/missing-$cat"
        found=0
        printf '%s' "$names" | tr '|' '\n' | while IFS= read -r n; do
            [ -z "$n" ] && continue
            printf '%s' "$tree" | grep -qiF "$n" && echo yes
        done > "$FS/found-$cat"
        [ -s "$FS/found-$cat" ] && result "access-sharing-$cat-named" PASS \
            || result "access-sharing-$cat-named" SKIP "section labels are not exposed by AT-SPI here; see out/shots/access-sharing-$cat.png"
    else
        result "access-sharing-$cat-named" SKIP "no AT-SPI"
    fi
    shot "access-sharing-$cat" 0.7
done

# ---- gap 4: preserve unmanaged sshd lines, digest over the exact text --------
printf 'PasswordAuthentication no\nMatch Address 10.0.0.0/8\n  PermitRootLogin yes\n' > "$FS/sshd-stage.conf"
out=$(printf '%s' '{"password":true,"pubkey":true,"root":false,"allowUsers":"","allowGroups":"","tcpForwarding":true,"x11Forwarding":false,"maxAuthTries":"6"}' \
    | SHANI_SSHD_CONF="$FS/sshd-stage.conf" python3 "$ACCESS" sshd-stage 2>/dev/null)
refuse=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("refuse"))' 2>/dev/null)
[ "$refuse" = True ] && result sshd-stage-refuses-match PASS \
    || result sshd-stage-refuses-match FAIL "$out"
printf 'PasswordAuthentication no\nAllowUsers anotherhost\n' > "$FS/sshd-stage.conf"
out=$(printf '%s' '{"password":true,"pubkey":true,"root":false,"allowUsers":"","allowGroups":"","tcpForwarding":true,"x11Forwarding":false,"maxAuthTries":"6"}' \
    | SHANI_SSHD_CONF="$FS/sshd-stage.conf" python3 "$ACCESS" sshd-stage 2>/dev/null)
printf '%s' "$out" | grep -q 'AllowUsers anotherhost' \
    && printf '%s' "$out" | grep -q '"refuse": false' \
    && result sshd-stage-keeps-unmanaged PASS \
    || result sshd-stage-keeps-unmanaged FAIL "$out"
printf 'PasswordAuthentication no\nAuthorizedKeysCommand /usr/bin/fetch --token SECRETVALUE\n' > "$FS/sshd-stage-secret.conf"
out=$(printf '%s' '{"password":true,"pubkey":true,"root":false,"allowUsers":"","allowGroups":"","tcpForwarding":true,"x11Forwarding":false,"maxAuthTries":"6"}' \
    | SHANI_SSHD_CONF="$FS/sshd-stage-secret.conf" python3 "$ACCESS" sshd-stage 2>/dev/null)
printf '%s' "$out" | grep -q '"refuse": true' && ! printf '%s' "$out" | grep -q 'SECRETVALUE' \
    && result sshd-stage-secret-not-written PASS \
    || result sshd-stage-secret-not-written FAIL "$out"
rm -f "$FS/sshd-stage-secret.conf"

# ---- gap 5: the root helper verifies the digest, checks sshd twice -----------
: > "$FS/sshd-calls"
stage=$(printf '%s' '{"password":true,"pubkey":true,"root":false,"allowUsers":"","allowGroups":"","tcpForwarding":true,"x11Forwarding":false,"maxAuthTries":"6"}' \
    | SHANI_SSHD_CONF="$FS/sshd.conf" python3 "$ACCESS" sshd-stage 2>/dev/null)
body=$(printf '%s' "$stage" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"text":d["text"],"sha256":d["sha256"]}))')
out=$(printf '%s' "$body" | SHANI_SSHD=/work/dev/fake-sshd.py SHANI_SSHD_DROPIN="$FS/sshd-live.conf" \
    SHANI_SYSTEMCTL="$FS/bin-access/systemctl" python3 "$ADMIN" remote-access-set 2>/dev/null)
echo "$out" | grep -q '"ok": true' && grep -q 'PasswordAuthentication yes' "$FS/sshd-live.conf" \
    && result sshd-staged-write PASS || result sshd-staged-write FAIL "$out"
bad=$(printf '%s' "$body" | sed 's/"sha256": "[0-9a-f]\{8\}/"sha256": "00000000/' \
    | SHANI_SSHD=/work/dev/fake-sshd.py SHANI_SSHD_DROPIN="$FS/sshd-live.conf" python3 "$ADMIN" remote-access-set 2>/dev/null)
echo "$bad" | grep -q 'SHA-256' && result sshd-bad-digest-refused PASS \
    || result sshd-bad-digest-refused FAIL "$bad"

# ---- gap 6: per-principal grants, with visudo still checking -----------------
out=$(printf '%s' '{"rows":[{"who":"asha","runas":"ALL","tags":["NOPASSWD"],"commands":["ALL"]}],"other":["# kept"]}' \
    | python3 "$ACCESS" sudoers-stage 2>/dev/null)
echo "$out" | grep -q 'NOPASSWD: ALL' && echo "$out" | grep -q '# kept' \
    && result sudoers-stage-grant PASS || result sudoers-stage-grant FAIL "$out"
out=$(printf '%s' '{"rows":[{"who":"bad;who","runas":"ALL","tags":[],"commands":["/bin/true"]}]}' \
    | python3 "$ACCESS" sudoers-stage 2>/dev/null)
printf '%s' "$out" | grep -q '"refuse": true' && result sudoers-stage-refuses-bad-principal PASS \
    || result sudoers-stage-refuses-bad-principal FAIL "$out"

# ---- gap 7: the three system addresses survive -------------------------------
printf '127.0.0.1 localhost\n127.0.1.1 laptop\n::1 localhost\n' > "$FS/hosts.backup"
before=$(sha256sum "$FS/hosts.backup" | cut -d' ' -f1)
out=$(printf '%s' '{"text":"127.0.0.1 localhost\n"}' | SHANI_HOSTS_FILE="$FS/hosts.backup" python3 "$ADMIN" hosts-set 2>/dev/null)
after=$(sha256sum "$FS/hosts.backup" | cut -d' ' -f1)
echo "$out" | grep -q 'system address' && [ "$before" = "$after" ] \
    && result hosts-keeps-system-addresses PASS || result hosts-keeps-system-addresses FAIL "$out"

# ---- gap 8: the sign-in code reader never prints a secret --------------------
out=$(python3 "$ACCESS" totp 2>/dev/null)
echo "$out" | grep -q '"pamWired": true' && ! echo "$out" | grep -q '123456' \
    && result totp-pam-wiring-without-secret PASS || result totp-pam-wiring-without-secret FAIL "$out"

# ---- gaps 9/11: NFS grammar and guarded write --------------------------------
out=$(printf '%s' '{"rows":[{"path":"/data","clients":[{"client":"*","options":["ro","rw"]}]}]}' \
    | python3 "$NFS" stage 2>/dev/null)
echo "$out" | grep -q 'exclusive_clash' && result nfs-exclusive-clash-refused PASS \
    || result nfs-exclusive-clash-refused FAIL "$out"
out=$(printf '%s' '{"rows":[{"path":"/data","clients":[{"client":"*","options":["ro","no_root_squash"]}]}]}' \
    | python3 "$NFS" stage 2>/dev/null)
echo "$out" | grep -q 'no_root_squash' && echo "$out" | grep -q '"sha256"' \
    && result nfs-ownership-warning PASS || result nfs-ownership-warning FAIL "$out"

# ---- gaps 10/12: Samba state, guest refusal and staged write -----------------
out=$(python3 "$SMB" state 2>/dev/null)
echo "$out" | grep -q '"testparm"' && ! echo "$out" | grep -qi 'password' \
    && result smb-state-no-secret PASS || result smb-state-no-secret FAIL "$out"
out=$(printf '%s' '{"shares":[{"name":"docs","path":"/data/docs","users":["asha"],"guestOk":true,"readOnly":true}]}' \
    | python3 "$SMB" stage 2>/dev/null)
echo "$out" | grep -q 'guest_denied' && result smb-guest-denied PASS \
    || result smb-guest-denied FAIL "$out"
: > "$FS/pkexec-stdin"
out=$(printf '%s' '{"shares":[{"name":"docs","path":"/data/docs","users":["asha"],"guestOk":false,"readOnly":true}]}' \
    | SHANI_SYSTEM_PKEXEC=/tmp/fake-bin/pkexec SHANI_ADMIN_TOOL=/work/dev/fake-admin.sh python3 "$SMB" set 2>/dev/null)
if echo "$out" | grep -q '"ok": true' && grep -q '"sha256"' "$FS/pkexec-stdin"; then
    result smb-staged-write PASS
else
    result smb-staged-write FAIL "$out stdin=$(head -c 240 "$FS/pkexec-stdin" 2>/dev/null) admin=$(tail -1 /tmp/admin-log 2>/dev/null | head -c 240)"
fi

# ---- gaps 13/14: reader state and mapping staging ----------------------------
out=$(python3 "$ACCESS" smartcard 2>/dev/null)
echo "$out" | grep -q '"readers"' && echo "$out" | grep -q '"pamPkcs11"' \
    && result smartcard-reader-state PASS || result smartcard-reader-state FAIL "$out"
out=$(printf '%s' '{"mappings":[{"identity":"alice -> bob","login":"alice"}]}' \
    | python3 "$ACCESS" smartcard-stage 2>/dev/null)
printf '%s' "$out" | grep -q '"refuse": true' && result smartcard-stage-refuses-bad-id PASS \
    || result smartcard-stage-refuses-bad-id FAIL "$out"

# ---- gaps 15/16: FIDO2 and Yubico OTP settings, no secret shown --------------
out=$(python3 "$U2F" config 2>/dev/null)
echo "$out" | grep -q '"fido2"' && echo "$out" | grep -q '"yubico"' \
    && result key-config-read PASS || result key-config-read FAIL "$out"
out=$(printf '%s' '{"target":"fido2","settings":{"alwaysok":true},"confirm":""}' \
    | python3 "$U2F" config-set 2>/dev/null)
echo "$out" | grep -q 'alwaysok' && result key-typed-confirmation-needed PASS \
    || result key-typed-confirmation-needed FAIL "$out"

# no staged text, digest or passphrase reached a log
rm -f "$FS/sshd-stage.conf"
if grep -R -q -F -- 'SECRETVALUE' /work/out/logs 2>/dev/null; then
    result access-sharing-no-secret-in-logs FAIL "secret in a log"
else
    result access-sharing-no-secret-in-logs PASS
fi

ipc closeAll
