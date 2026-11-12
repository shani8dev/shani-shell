#!/bin/sh
# firewall-cmd's stand-in for the suite: says firewalld is running, records
# every change in /tmp/firewall-log, and refuses when /tmp/firewall-refuse exists
echo "$@" >> /tmp/firewall-log
[ "$1" = --state ] && { echo running; exit 0; }
[ -e /tmp/firewall-refuse ] && { echo "Authorization failed." >&2; exit 11; }
echo success
