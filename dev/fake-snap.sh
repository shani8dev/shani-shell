#!/bin/sh
# stands in for snap (snapd cannot run in a container): a small Snap Store with
# real names, what is installed kept in $FAKE_SNAP_DIR, installs as slow as a
# download so the progress shows
D=${FAKE_SNAP_DIR:-/tmp/fake-snap}; mkdir -p "$D"; touch "$D/installed"
echo "$*" >> "$D/calls"
STORE='spotify	1.2.48	spotify✓	-	Music for everyone
obsidian	1.7.7	obsidianmd	classic	A knowledge base on local Markdown files
code	1.95	vscode✓	classic	Code editing. Redefined.
slack	4.41	slack✓	-	Team communication for the 21st century
discord	0.0.76	discord✓	-	All-in-one voice and text chat
postman	11.20	postman-inc✓	-	API development environment
zoom-client	6.2	zoom✓	-	Video meetings
telegram-desktop	5.8	telegram.desktop✓	-	Fast and secure messaging'
case "$1" in
find)
    printf 'Name  Version  Publisher  Notes  Summary\n'
    printf '%s\n' "$STORE" | grep -i -- "${2:-}" | awk -F'\t' '{printf "%s  %s  %s  %s  %s\n", $1, $2, $3, $4, $5}' ;;
list)
    printf 'Name  Version  Rev  Tracking  Publisher  Notes\ncore22  20241001  1663  latest/stable  canonical✓  base\nsnapd  2.66  23258  latest/stable  canonical✓  snapd\n'
    while read -r n; do [ -n "$n" ] && printf '%s\n' "$STORE" | awk -F'\t' -v n="$n" '$1 == n {printf "%s  %s  42  latest/stable  %s  %s\n", $1, $2, $3, $4}'; done < "$D/installed" ;;
refresh)
    if [ "${2:-}" = --list ]; then
        grep -qx spotify "$D/installed" && printf 'Name  Version  Rev  Size  Publisher  Notes\nspotify  1.2.50  83  190MB  spotify✓  -\n' || echo "All snaps up to date." >&2
    else echo "All snaps up to date."; fi ;;
install)
    for p in 10 45 80 100; do echo "Download snap \"$2\" ($p%)"; sleep 0.3; done
    grep -qx "$2" "$D/installed" || echo "$2" >> "$D/installed"; echo "$2 installed" ;;
remove) grep -vx "$2" "$D/installed" > "$D/i2"; mv "$D/i2" "$D/installed"; echo "$2 removed" ;;
esac
