#!/bin/sh
# usage: pam-test.sh GREETD_PAM_FILE   (inside shani-shell-dev; `sh dev/check.sh pam`)
# The lock screen's second conversation (data/pam.d/shani-lock-biometric) and the
# greeter's stack (shani-desktop-niri's etc/pam.d/shani-greetd) through the real
# libpam (dev/pam-auth.py: pam_start_confdir on a scratch confdir), with the
# hardware simulated by what the module file is: pam_permit.so copied as
# pam_u2f.so is a key touched, pam_deny.so one not touched, no file the package
# not installed - the same for pam_fprintd.so. The fingerprint flag the greeter
# leaves is a stand-in greeter-fingerprint that succeeds while /tmp/fp-flag exists.
# Then, when pam-u2f can be installed, the real module: no key registered or no
# key plugged in must fall through, never let anyone in.
GREETD=${1:-/desk/etc/pam.d/shani-greetd}
fail=0
result() { echo "RESULT $1 $2${3:+ ($3)}"; if [ "$2" = FAIL ]; then fail=1; fi; }   # a SKIP is not a failure
M=/usr/lib/security
C=/tmp/pamconf
mkdir -p $C /usr/lib/shani-desktop-niri
cp /work/data/pam.d/shani-lock-biometric $C/
cp "$GREETD" $C/shani-greetd
# what the greeter's includes stand for: a password checked by pam_unix
printf 'auth required pam_unix.so\naccount required pam_permit.so\npassword required pam_permit.so\nsession required pam_permit.so\n' > $C/system-local-login
printf '#!/bin/sh\ntest -e /tmp/fp-flag\n' > /usr/lib/shani-desktop-niri/greeter-fingerprint
chmod +x /usr/lib/shani-desktop-niri/greeter-fingerprint
[ -e $M/pam_gnome_keyring.so ] || cp $M/pam_permit.so $M/pam_gnome_keyring.so
id alice >/dev/null 2>&1 || useradd -m alice
echo "alice:right-password" | chpasswd
u2f() { case $1 in touch) cp $M/pam_permit.so $M/pam_u2f.so ;; miss) cp $M/pam_deny.so $M/pam_u2f.so ;; none) rm -f $M/pam_u2f.so ;; esac; }
fp() { case $1 in touch) cp $M/pam_permit.so $M/pam_fprintd.so ;; miss) cp $M/pam_deny.so $M/pam_fprintd.so ;; none) rm -f $M/pam_fprintd.so ;; esac; }
auth() { python3 /work/dev/pam-auth.py "$1" alice $C "${2:-}" 2>&1; }
expect() {   # expect <name> <success|fail> <service> [password]
    out=$(auth "$3" "${4:-}"); case "$out" in success*) got=success ;; *) got=fail ;; esac
    [ "$got" = "$2" ] && result "$1" PASS || result "$1" FAIL "$out"
}

# ---- the lock screen's biometric conversation ----
rm -f /tmp/fp-flag; fp none
u2f none;  expect pam-lock-no-u2f-module-fails fail shani-lock-biometric
u2f touch; expect pam-lock-key-touched-unlocks success shani-lock-biometric
u2f miss;  expect pam-lock-key-not-touched-stays-locked fail shani-lock-biometric
fp miss; u2f touch; expect pam-lock-key-after-a-finger-miss success shani-lock-biometric

# ---- the greeter ----
fp none; u2f touch
expect pam-greeter-key-touched-signs-in success shani-greetd wrong-password
u2f miss
expect pam-greeter-no-touch-password-works success shani-greetd right-password
expect pam-greeter-no-touch-wrong-password-fails fail shani-greetd wrong-password
u2f none
expect pam-greeter-no-u2f-module-password-works success shani-greetd right-password
# the fingerprint path: the flag takes it, and a miss ends the attempt (key or not)
touch /tmp/fp-flag
fp touch; u2f miss; expect pam-greeter-flag-finger-signs-in success shani-greetd wrong-password
fp miss;  u2f touch; expect pam-greeter-flag-finger-miss-ends-it fail shani-greetd right-password
rm -f /tmp/fp-flag
# no flag: the jump (default=2) skips the finger and pam_deny, onto the face, the key, the password
fp touch; u2f miss; expect pam-greeter-no-flag-skips-the-finger fail shani-greetd wrong-password
fp none; u2f none

# ---- the real pam_u2f (when the package can be fetched): never a way in on its own ----
if pacman -Sy --noconfirm --needed pam-u2f >/dev/null 2>&1; then
    rm -rf /home/alice/.config/Yubico
    expect pam-real-u2f-no-key-registered-falls-through fail shani-lock-biometric
    expect pam-real-u2f-greeter-no-key-password-works success shani-greetd right-password
    mkdir -p /home/alice/.config/Yubico
    echo "alice:aGFuZGxl,cHVia2V5,es256,+presence" > /home/alice/.config/Yubico/u2f_keys
    chown -R alice /home/alice/.config
    expect pam-real-u2f-registered-but-unplugged-falls-through fail shani-lock-biometric
    expect pam-real-u2f-greeter-unplugged-wrong-password-fails fail shani-greetd wrong-password
    rm -f $M/pam_u2f.so
else
    echo "(pam-u2f could not be installed here: the real module's checks were skipped)"
fi
exit $fail
