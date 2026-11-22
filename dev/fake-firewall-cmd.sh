#!/bin/sh
# firewall-cmd's stand-in for the suite: says firewalld is running, answers the
# reads with a plausible pair of zones, records every change in /tmp/firewall-log,
# and refuses when /tmp/firewall-refuse exists
echo "$@" >> /tmp/firewall-log
[ "$1" = --state ] && { echo running; exit 0; }
[ "$1" = --get-default-zone ] && { echo public; exit 0; }
[ "$1" = --list-all-zones ] && {
    cat <<'ZONES'
block
  target: %%REJECT%%
  interfaces:
  sources:
  services:
  ports:
  protocols:
  forward-ports:
  source-ports:
  icmp-blocks:
  rich rules:

drop
  target: DROP
  interfaces:
  sources:
  services:
  ports:
  protocols:
  forward-ports:
  source-ports:
  icmp-blocks:
  rich rules:

home (active)
  target: default
  icmp-block-inversion: no
  interfaces:
  sources:
  services: dhcpv6-client samba-client ssh
  ports:
  protocols:
  forward-ports:
  source-ports:
  icmp-blocks:
  rich rules:

public (active)
  target: default
  icmp-block-inversion: no
  interfaces: wlan0
  sources:
  services: dhcpv6-client ssh
  ports: 631/udp 631/tcp
  protocols:
  forward-ports:
  source-ports:
  icmp-blocks:
  rich rules:

trusted
  target: ACCEPT
  interfaces:
  sources:
  services:
  ports:
  protocols:
  forward-ports:
  source-ports:
  icmp-blocks:
  rich rules:
ZONES
    exit 0
}
[ -e /tmp/firewall-refuse ] && { echo "Authorization failed." >&2; exit 11; }
echo success