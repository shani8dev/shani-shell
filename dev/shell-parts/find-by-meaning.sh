# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=find-by-meaning)
# ---- the launcher asks Chronoa's file index (Agent.FindFiles) ----
# the mock's FindFiles is a keyword scan of ~/Documents; the real one is by meaning
mkdir -p /root/Documents
printf 'Electricity bill for March from City Power\n' > /root/Documents/scan0001.txt
ipc launcher "electricity bill"
waitfor "d['launcherMeaning'] >= 1" 8 && result launcher-finds-by-meaning PASS || result launcher-finds-by-meaning FAIL "$(q "['launcherMeaning']")"
sleep 0.5; shot launcher-by-meaning 0.2
ipc closeAll; rm -f /root/Documents/scan0001.txt
