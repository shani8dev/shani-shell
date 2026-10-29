#!/bin/sh
# systemctl, for the remote-desktop test: `--user` knows one unit, Sunshine's,
# on or off in /tmp/sun-on; everything else is the real systemctl
[ "$1" = --user ] || exec /usr/bin/systemctl "$@"
echo "$*" >> /tmp/systemctl-user.log
case "$2" in
    cat) [ "$3" = app-dev.lizardbyte.app.Sunshine.service ] ;;
    is-active) [ -f /tmp/sun-on ] ;;
    enable) touch /tmp/sun-on ;;
    disable) rm -f /tmp/sun-on ;;
    *) exit 0 ;;
esac
