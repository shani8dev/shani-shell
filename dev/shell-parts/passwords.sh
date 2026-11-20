# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=passwords)
# ---- Passwords and Keys (Seahorse parity), against the session's own oo7: a saved
#      password listed and shown on request, one added from the window, a GPG key
#      made and listed ----
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
printf 'pw-for-home' | secret-tool store --label="Wi-Fi: Home" service wifi ssid Home 2>/dev/null
SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani app passwords >/dev/null 2>&1
waitfor "d['passwordsShown'] and 'Wi-Fi: Home' in d['passwordsItems']" 8 && result passwords-listed PASS || result passwords-listed FAIL "$(q "['passwordsShown'], d['passwordsItems']")"
shot app-passwords 0.3
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "button:^Show Wi-Fi: Home$" >/dev/null 2>&1
    waitfor "d['passwordsRevealed'] == 'Wi-Fi: Home'" 6 && result passwords-revealed PASS || result passwords-revealed FAIL "$(q "['passwordsRevealed']")"
fi
# a GPG key made (the passphrase through gpg's loopback, never a command line)
printf 'key-pass\n' | python3 /work/bridge/passwords.py gpg-new "Asha Patil" asha@example.org >/dev/null
ipc closeAll; SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani app passwords >/dev/null 2>&1
waitfor "'Asha Patil <asha@example.org>' in d['passwordsKeys']" 10 && result passwords-gpg-key PASS || result passwords-gpg-key FAIL "$(q "['passwordsKeys']")"
ipc closeAll
