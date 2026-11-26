#!/bin/sh
# Harness stand-in for pkexec: approve without a password, log what was asked,
# then run the real argv. Used by the system pages' privileged *reads* (boot
# verification, storage analysis, audit events, UPS policy save). No secret is
# ever in this log: the bridges pass those on stdin.
printf '%s\n' "$*" >> "${FAKE_PKEXEC_LOG:-/tmp/fake-system/pkexec-calls}"
exec "$@"
