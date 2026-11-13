# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=app-menu)
# ---- the app's own menus in the window menu (Services/AppMenu, bridge/appmenu.py) ----
# A GTK 3 app with a menu bar (dev/menubar-app.py): its File and Edit menus are read
# from its accessibility tree, a click reaches it, and a submenu's item too; an app
# that shows no menu bar gets its desktop actions instead.
rm -f /tmp/menubar-saved
GDK_BACKEND=wayland python3 /work/dev/menubar-app.py >/dev/null 2>&1 &
MPID=$!
i=0; until niri msg -j focused-window 2>/dev/null | grep -q "Menu bar test" || [ $i -ge 40 ]; do sleep 0.25; i=$((i+1)); done
[ "$(q "['windowPid']")" = "$MPID" ] && result app-menu-window-has-its-pid PASS || result app-menu-window-has-its-pid FAIL "niri says $(q "['windowPid']"), the app is $MPID"

ipc windowMenu
waitfor "d['appMenus'] == ['File', 'Edit'] and not d['appMenuLoading']" 8 \
    && result app-menu-read PASS "$(q "['appMenus']")" || result app-menu-read FAIL "menus $(q "['appMenus']"), why '$(q "['appMenuWhy']")'"
q "['appMenuItems'][0]" | grep -q "Save Ctrl+S" && q "['appMenuItems'][0]" | grep -q "Recent >" \
    && result app-menu-shortcuts-and-submenus PASS "$(q "['appMenuItems'][0]")" || result app-menu-shortcuts-and-submenus FAIL "$(q "['appMenuItems']")"
ipc windowMenuOpenApp 0; sleep 0.8; shot window-menu-app-menus 0.2

# a click reaches the app: File > Save, and File > Recent > b.txt (a submenu's item)
ipc closeAll
ipc appMenuActivate "0/1"
for i in $(seq 20); do grep -q '^Save$' /tmp/menubar-saved 2>/dev/null && break; sleep 0.2; done
grep -q '^Save$' /tmp/menubar-saved 2>/dev/null && result app-menu-click-reaches-the-app PASS || result app-menu-click-reaches-the-app FAIL "the app did '$(cat /tmp/menubar-saved 2>&1)'"
ipc appMenuActivate "0/2/1"
for i in $(seq 20); do grep -q '^b.txt$' /tmp/menubar-saved 2>/dev/null && break; sleep 0.2; done
grep -q '^b.txt$' /tmp/menubar-saved 2>/dev/null && result app-menu-submenu-item PASS || result app-menu-submenu-item FAIL "the app did '$(cat /tmp/menubar-saved 2>&1)'"
kill $MPID 2>/dev/null

# an app with no menu bar of its own (gnome-text-editor: GTK 4, a popover menu):
# no app menus, and its desktop actions ("New Window") in the window menu instead
gnome-text-editor >/dev/null 2>&1 &
i=0; until niri msg -j focused-window 2>/dev/null | grep -qi "texteditor" || [ $i -ge 40 ]; do sleep 0.25; i=$((i+1)); done
sleep 1
ipc windowMenu
waitfor "not d['appMenuLoading'] and d['appMenus'] == [] and 'New Window' in d['windowMenuLabels']" 8 \
    && result app-menu-falls-back-to-desktop-actions PASS "$(q "['appMenuWhy']")" \
    || result app-menu-falls-back-to-desktop-actions FAIL "menus $(q "['appMenus']"), rows $(q "['windowMenuLabels'][:4]")"
ipc closeAll
pkill -f gnome-text-editor
