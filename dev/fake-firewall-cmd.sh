#!/bin/sh
# firewall-cmd's stand-in for the suite: says firewalld is running, answers the
# reads with a plausible set of zones, records every change in /tmp/firewall-log,
# and refuses when /tmp/firewall-refuse exists.
#
# The zones it reports live in /tmp/firewall-zones, one line each as
#   name|active|services|ports|protocols|rich|interfaces
# (rich rules separated by ";"), and the default zone in /tmp/firewall-default.
# A test can therefore change them - a rule added, a zone created - and read the
# change back the way a person would. Both are seeded on first use and survive
# between parts. --runtime-to-permanent is accepted and ignored: the stand-in has
# no runtime to lose.
echo "$@" >> /tmp/firewall-log
Z=/tmp/firewall-zones
D=/tmp/firewall-default

seed() {
    [ -s "$Z" ] || cat > "$Z" <<'ZONES'
block|0|target=%%REJECT%%|||
drop|0|target=DROP|||
home|1|dhcpv6-client samba-client ssh||||
public|1|dhcpv6-client ssh|631/udp 631/tcp|||wlan0
trusted|0|target=ACCEPT|||
ZONES
    [ -s "$D" ] || echo public > "$D"
}

seed

# name as firewall-cmd prints it in --list-all-zones, with "(active)"
shown_name() { if [ "$2" = 1 ]; then printf '%s (active)' "$1"; else printf '%s' "$1"; fi; }

show() {   # name|active|services|ports|protocols|rich|interfaces
    name=$(printf '%s' "$1" | cut -d'|' -f1)
    active=$(printf '%s' "$1" | cut -d'|' -f2)
    services=$(printf '%s' "$1" | cut -d'|' -f3)
    ports=$(printf '%s' "$1" | cut -d'|' -f4)
    protocols=$(printf '%s' "$1" | cut -d'|' -f5)
    rich=$(printf '%s' "$1" | cut -d'|' -f6)
    ifaces=$(printf '%s' "$1" | cut -d'|' -f7)
    target=default
    case " $services " in
        *" target="*)
            target=$(printf '%s' "$services" | sed -n 's/.*target=\([^ ]*\).*/\1/p')
            services=$(printf '%s' "$services" | sed 's/target=[^ ]*//; s/  */ /g; s/^ //; s/ $//')
            ;;
    esac
    printf '%s\n' "$(shown_name "$name" "$active")"
    printf '  target: %s\n' "${target:-default}"
    printf '  icmp-block-inversion: no\n'
    printf '  interfaces: %s\n' "$ifaces"
    printf '  sources:\n'
    printf '  services: %s\n' "$services"
    printf '  ports: %s\n' "$ports"
    printf '  protocols: %s\n' "$protocols"
    printf '  forward-ports:\n'
    printf '  source-ports:\n'
    printf '  icmp-blocks:\n'
    printf '  rich rules:\n'
    printf '%s\n' "$rich" | tr ';' '\n' | sed '/^$/d; s/^/    /'
}

set_field() {   # python-index column, value, zone, add|del
    python3 - "$Z" "$3" "$1" "$2" "$4" <<'PY'
import sys
path, zone, col, value, op = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
sep = " " if col != 5 else ";"
lines = open(path, encoding="utf-8").read().split("\n")
out = []
for ln in lines:
    p = ln.split("|")
    if p[0] == zone:
        while len(p) <= col:
            p.append("")
        cur = [x for x in p[col].split(sep) if x]
        cur = [x for x in cur if x != value] + ([value] if op == "add" else [])
        p[col] = sep.join(cur)
        ln = "|".join(p)
    out.append(ln)
open(path, "w", encoding="utf-8").write("\n".join(out))
PY
}

zone_exists() { cut -d'|' -f1 "$Z" | grep -qx -- "$1"; }

[ "$1" = --state ] && { echo running; exit 0; }
[ "$1" = --get-default-zone ] && { cat "$D"; exit 0; }
[ "$1" = --get-zones ] && { cut -d'|' -f1 "$Z" | tr '\n' ' '; echo; exit 0; }
[ "$1" = --list-all-zones ] && {
    while IFS= read -r row; do [ -n "$row" ] && show "$row"; done < "$Z"
    exit 0
}
[ "$1" = --info-zone ] || [ "${1#--info-zone=}" != "$1" ] && {
    show "$(grep "^${1#--info-zone=}|" "$Z")"; exit 0
}

[ -e /tmp/firewall-refuse ] && { echo "Authorization failed." >&2; exit 11; }

# ---- a change ---------------------------------------------------------------
zone=""
for a in "$@"; do case "$a" in --zone=*) zone=${a#--zone=} ;; esac; done

if [ -n "$zone" ] && ! zone_exists "$zone"; then
    echo "Error: INVALID_ZONE: $zone" >&2; exit 1
fi

for a in "$@"; do
    case "$a" in
        --permanent|--state|--runtime-to-permanent) ;;
        --set-default-zone=*)
            n=${a#--set-default-zone=}
            zone_exists "$n" || { echo "Error: INVALID_ZONE: $n" >&2; exit 1; }
            echo "$n" > "$D" ;;
        --new-zone=*)
            n=${a#--new-zone=}
            if zone_exists "$n"; then echo "Error: ZONE_CONFLICT: $n" >&2; exit 1; fi
            printf '%s|0||||\n' "$n" >> "$Z" ;;
        --delete-zone=*)
            n=${a#--delete-zone=}
            [ "$n" = "$(cat "$D")" ] && { echo "Error: INVALID_ZONE: $n is the default" >&2; exit 1; }
            grep -v "^$n|" "$Z" > "$Z.tmp" && mv "$Z.tmp" "$Z" ;;
        --add-rich-rule=*)    set_field 5 "${a#--add-rich-rule=}" "$zone" add ;;
        --remove-rich-rule=*) set_field 5 "${a#--remove-rich-rule=}" "$zone" del ;;
        --add-service=*)      set_field 2 "${a#--add-service=}" "$zone" add ;;
        --remove-service=*)   set_field 2 "${a#--remove-service=}" "$zone" del ;;
        --add-port=*)         set_field 3 "${a#--add-port=}" "$zone" add ;;
        --remove-port=*)      set_field 3 "${a#--remove-port=}" "$zone" del ;;
        --add-protocol=*)     set_field 4 "${a#--add-protocol=}" "$zone" add ;;
        --remove-protocol=*)  set_field 4 "${a#--remove-protocol=}" "$zone" del ;;
    esac
done

echo success