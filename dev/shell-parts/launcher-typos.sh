# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=launcher-typos)
# ---- the launcher forgives a typo: apps and actions, below every real match ----------------
ipc launcher "calcualtor"
waitfor "d['topResult'] == 'Calculator'" 4 && result launcher-typo-app PASS || result launcher-typo-app FAIL "$(q "['topResult']")"
ipc closeAll; ipc launcher "settngs"
waitfor "'settings' in (d['topResult'] or '').lower()" 4 && result launcher-typo-action PASS || result launcher-typo-action FAIL "$(q "['topResult']")"
# what was typed exactly still comes first
ipc closeAll; ipc launcher "text edi"
waitfor "d['topResult'] == 'Text Editor'" 4 && result launcher-exact-before-typo PASS || result launcher-exact-before-typo FAIL "$(q "['topResult']")"
ipc closeAll
