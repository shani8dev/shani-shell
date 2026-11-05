#!/bin/sh
# Stands in for libfido2's fido2-token (no security key in a container): `-L`
# lists one YubiKey while /tmp/fido-key exists, as the real one prints it.
[ "$1" = -L ] || exit 1
[ -e "${FAKE_FIDO_KEY:-/tmp/fido-key}" ] && echo "/dev/hidraw4: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO+CCID)"
exit 0
