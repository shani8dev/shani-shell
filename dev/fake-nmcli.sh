#!/bin/sh
# nmcli, for the saved-networks test: one Wi-Fi network whose metered and
# autoconnect settings live in /tmp/nm-*; every call is written to /tmp/nm-log
echo "$*" >> /tmp/nm-log
case "$*" in
    "-t -f UUID,TYPE,AUTOCONNECT,NAME connection show") echo "u-home:802-11-wireless:$(cat /tmp/nm-auto 2>/dev/null || echo yes):Home\:Wi-Fi" ;;
    "-g connection.metered connection show u-home") cat /tmp/nm-metered 2>/dev/null || echo no ;;
    "connection modify u-home connection.metered "*) echo "$5" > /tmp/nm-metered ;;
    "connection modify u-home connection.autoconnect "*) echo "$5" > /tmp/nm-auto ;;
esac
exit 0
