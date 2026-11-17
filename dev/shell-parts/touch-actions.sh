# The dock's Menu key must still arm then empty the bin after adding long press.
# This only runs inside the disposable dev container; all its trash is fixtures.
settings '{"dockVisibility":"always","dockTrash":true}'
fixture=$(mktemp /tmp/touch-trash-XXXXXX)
printf 'fixture\n' > "$fixture"
gio trash "$fixture"
waitfor "d['trashCount'] > 0" 5
ipc focusDock
i=0
while [ "$(q "['navFocus']")" != Trash ] && [ "$i" -lt 40 ]; do
    wtype -k Right
    sleep 0.1
    i=$((i+1))
done
if [ "$(q "['navFocus']")" = Trash ]; then
    wtype -k Menu
    sleep 0.3
    [ "$(q "['trashCount']")" -gt 0 ] && result touch-trash-first-menu-only-arms PASS \
        || result touch-trash-first-menu-only-arms FAIL
    wtype -k Menu
    waitfor "d['trashCount'] == 0" 5 && result touch-trash-second-menu-empties PASS \
        || result touch-trash-second-menu-empties FAIL
else
    result touch-trash-keyboard-reachable FAIL "$(q "['navFocus']")"
fi
ipc closeAll
settings '{}'
