# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=clipboard-phone)
# ---- the clipboard history says what came from the phone (Shani Link's clipboard sync) ----
# shani-link's clipboard_sync.py writes clipboard-origin.json when the phone's text
# arrives (tested there against a fake phone); here: the shell reads it
mkdir -p /root/.local/state/shani-link
printf '{"copied on the phone: the address": {"device": "Pixel 9", "at": %s}}' "$(date +%s)" > /root/.local/state/shani-link/clipboard-origin.json
printf 'copied on the phone: the address' | wl-copy; sleep 0.5; printf 'copied here' | wl-copy; sleep 0.5
ipc launcher "c "
waitfor "any(x.startswith('Pixel 9: copied on the phone') for x in d['clipFromPhone']) and len(d['clipFromPhone']) == 1" 8 \
    && result clipboard-from-phone-attributed PASS || result clipboard-from-phone-attributed FAIL "$(q "['clipFromPhone']")"
sleep 0.6; shot clipboard-from-phone 0.2
ipc closeAll
