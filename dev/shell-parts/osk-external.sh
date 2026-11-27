# Verify the same keyboard path in a separate Wayland client, on a phone.
# foot writes exactly what it receives. No a11y or clipboard readback is needed.
ipc dismissAll
# The shell sends foot a theme signal after writing its config. Wait before
# starting the fixture so foot has its signal handlers by the next update.
waitfor "d['terminalFoot'] != ''" 6
sleep 0.8
external_text=/tmp/shani-osk-external-text
rm -f "$external_text"
foot -a shani-osk-external -T "External keyboard test" sh -c '
    IFS= read -r line
    printf "%s" "$line" > "$1"
    sleep 15
' sh "$external_text" >/tmp/shani-osk-external.log 2>&1 &
external_pid=$!

window_height() {
    niri msg -j focused-window | python3 -c '
import json, sys
window = json.load(sys.stdin)
if window and window["app_id"] == "shani-osk-external":
    print(round(window["layout"]["tile_size"][1]))
'
}

i=0
while [ -z "$(window_height)" ] && [ "$i" -lt 20 ]; do
    sleep 0.25
    i=$((i + 1))
done
before=$(window_height)
ipc osk
waitfor "d['osk'] and d['oskHeight'] > 0" 5
sleep 0.6
after=$(window_height)
if [ -n "$before" ] && [ -n "$after" ] && [ "$after" -lt "$before" ]; then
    result osk-reserves-space-without-taking-focus PASS
else
    result osk-reserves-space-without-taking-focus FAIL "window height before: $before, after: $after"
fi

for key in t e h space; do
    ipc oskPress "$key"
    sleep 0.2
done
ipc oskLanguage
waitfor "d['oskLang'] == 'mr'" 3
for key in न म स ् त ए; do
    ipc oskPress "$key"
    sleep 0.2
done
waitfor "d['oskTyped'] == '' and d['oskCorrection'] == '' and not d['oskPredicted']" 3 \
    && result osk-external-keeps-no-typing-context PASS \
    || result osk-external-keeps-no-typing-context FAIL
ipc oskPress Return
i=0
while [ ! -f "$external_text" ] && [ "$i" -lt 20 ]; do
    sleep 0.25
    i=$((i + 1))
done
if [ "$(cat "$external_text" 2>/dev/null)" = "teh नमस्ते" ]; then
    result osk-types-literally-into-wayland-app PASS
else
    result osk-types-literally-into-wayland-app FAIL "unexpected terminal input"
fi
shot osk-external-app 0.3
ipc osk
waitfor "not d['osk'] and d['oskHeight'] == 0" 4 \
    && result osk-releases-reserved-space PASS || result osk-releases-reserved-space FAIL
kill "$external_pid" 2>/dev/null || true
