#!/bin/sh
# Stands in for yubikey-manager's `ykman` (no security key in a container): a key
# holding three OATH accounts - one plain, one that wants a touch, one counter-based.
# SHANI_FAKE_YKMAN_NONE=1: no key is connected.
[ -n "${SHANI_FAKE_YKMAN_NONE:-}" ] && { echo "ERROR: No YubiKey detected!" >&2; exit 2; }
# SHANI_FAKE_YKMAN_LOCKED=1: its OATH codes are behind a password
[ -n "${SHANI_FAKE_YKMAN_LOCKED:-}" ] && { echo "Enter the password: " ; echo "Error: Authentication to the YubiKey failed. Wrong password?" >&2; exit 1; }
case "$*" in
    "oath accounts code") printf 'GitHub:me@example.com           %s\nBank:savings                     [Requires Touch]\nVPN:office                       [HOTP Account]\n' 482913 ;;
    "oath accounts code --single Bank:savings") sleep 0.3; echo 731044 ;;
    *) echo "ERROR: no such account" >&2; exit 2 ;;
esac
