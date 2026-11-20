# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=files-extras)
# ---- Files: type to find, zoom, tabs, turn the selection over, stars, free space,
#      templates - driven by real keystrokes (wtype) where a person would type ----
E=/tmp/files-extras; rm -rf $E; mkdir -p $E/sub "$HOME/Templates"
for n in apple banana cherry date; do printf x > "$E/$n.txt"; done
printf 'tpl' > "$HOME/Templates/Letter.txt"
rm -f "$HOME/.local/share/shani-shell/starred"
ipc filesOpen "$E"; sleep 1.5
# type to find
wtype "ch"; sleep 0.6
[ "$(q "['filesSelectedNames']")" = "['cherry.txt']" ] && result files-type-to-find PASS || result files-type-to-find FAIL "$(q "['filesSelectedNames']")"
sleep 1.2
# Ctrl+Shift+I: everything else chosen
wtype -M ctrl -M shift -k i -m shift -m ctrl; sleep 0.6
[ "$(q "['filesSelectedNames']")" = "['sub', 'apple.txt', 'banana.txt', 'date.txt']" ] && result files-invert-selection PASS || result files-invert-selection FAIL "$(q "['filesSelectedNames']")"
# Ctrl+plus twice, Ctrl+0
wtype -M ctrl -k plus -m ctrl; wtype -M ctrl -k plus -m ctrl; sleep 0.4
z=$(q "['filesZoom']"); wtype -M ctrl -k 0 -m ctrl; sleep 0.4
[ "$z" = 1.4 ] && [ "$(q "['filesZoom']")" = 1 ] && result files-zoom PASS || result files-zoom FAIL "after plus $z, after 0 $(q "['filesZoom']")"
# Ctrl+T: a second tab here; it walks on its own; Ctrl+Tab back; Ctrl+W
wtype -M ctrl -k t -m ctrl; sleep 0.5; ipc filesOpen "$E/sub"; sleep 0.8
wtype -M ctrl -k Tab -m ctrl; sleep 0.8
[ "$(q "['filesTabs']")" = "['$E', '$E/sub']" ] && [ "$(q "['filesPath']")" = "$E" ] && result files-tabs PASS || result files-tabs FAIL "$(q "['filesTabs'], d['filesTabIndex'], d['filesPath']")"
shot files-tabs 0.2
wtype -M ctrl -k w -m ctrl; sleep 0.6
[ "$(q "['filesTabs']")" = "['$E/sub']" ] && result files-tab-close PASS || result files-tab-close FAIL "$(q "['filesTabs'], d['filesPath']")"
ipc filesOpen "$E"; sleep 1
# stars: starred, then the Starred place lists it
ipc filesStar "$E/banana.txt" true; sleep 0.8
ipc filesOpen "starred:"
waitfor "d['filesEntries'] == 1 and d['filesPath'] == 'starred:'" 6 && result files-starred-place PASS || result files-starred-place FAIL "$(q "['filesStarred'], d['filesEntries'], d['filesPath']")"
# free space said, templates offered
ipc filesOpen "$E"; sleep 1
[ "$(q "['filesFree']")" != "-1" ] && result files-free-space PASS || result files-free-space FAIL "$(q "['filesFree']")"
[ "$(q "['filesTemplates']")" = "['Letter']" ] && result files-templates PASS || result files-templates FAIL "$(q "['filesTemplates']")"
# Properties: "Run as a program" pressed through AT-SPI sets the run bits; Undo puts them back
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
if [ -f "$A11Y" ]; then
    printf '#!/bin/sh\n' > $E/run.sh; chmod 644 $E/run.sh; sleep 0.8
    ipc filesProps "$E/run.sh"; sleep 1.2
    timeout 20 python3 "$A11Y" press "check box:^Run as a program$" >/dev/null 2>&1; sleep 1
    m=$(stat -c %a $E/run.sh)
    ipc filesUndo; sleep 1
    [ "$m" = 755 ] && [ "$(stat -c %a $E/run.sh)" = 644 ] && result files-run-as-program PASS || result files-run-as-program FAIL "after press $m, after undo $(stat -c %a $E/run.sh)"
fi
# Open in terminal: the desktop's terminal (xdg-terminal-exec), started inside the folder
printf '#!/bin/sh\npwd > /tmp/terminal-opened-in\n' > /usr/local/bin/xdg-terminal-exec; chmod +x /usr/local/bin/xdg-terminal-exec
rm -f /tmp/terminal-opened-in; ipc filesTerminal "$E/sub"; sleep 1
[ "$(cat /tmp/terminal-opened-in 2>/dev/null)" = "$E/sub" ] && result files-open-in-terminal PASS || result files-open-in-terminal FAIL "$(cat /tmp/terminal-opened-in 2>&1)"
rm -f /usr/local/bin/xdg-terminal-exec
rm -rf $E "$HOME/Templates/Letter.txt" "$HOME/.local/share/shani-shell/starred"; ipc closeAll
