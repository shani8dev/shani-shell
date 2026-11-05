#!/bin/sh
# Stands in for pam-u2f's pamu2fcfg: the key "touched" while /tmp/fido-key exists.
# Prints a credential as the real one does - "user:handle,key,es256,+presence", or
# with -n only ":handle,…" for appending - each one different; calls go to /tmp/u2f-log.
echo "$*" >> "${FAKE_U2F_LOG:-/tmp/u2f-log}"
[ -e "${FAKE_FIDO_KEY:-/tmp/fido-key}" ] || { echo "No device found. Aborting." >&2; exit 1; }
u=; n=
while [ $# -gt 0 ]; do case "$1" in -u) u=$2; shift ;; -n) n=1 ;; esac; shift; done
c="h$(date +%s%N | tail -c 7)==,pk$$==,es256,+presence"
[ -n "$n" ] && echo ":$c" || echo "$u:$c"
