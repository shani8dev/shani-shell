# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=whats-new)
# ---- "What's new" after an update ------------------------------------------------
# /etc/shani-version (session.sh writes 0.0.0-test) vs the last version in
# Quickshell state: a changed version is told once, then recorded.
waitfor "d['whatsNewVersion'] == '0.0.0-test'" 5 && result whats-new-reads-version PASS || result whats-new-reads-version FAIL "$(q "['whatsNewVersion']")"
# first sighting records silently: nothing told, version stored
waitfor "d['whatsNewShown'] == ''" 3 && result whats-new-first-install-silent PASS || result whats-new-first-install-silent FAIL "$(q "['whatsNewShown']")"
printf '9.9.9-test\n' > /etc/shani-version
ipc whatsNewCheck
waitfor "d['whatsNewShown'] == '9.9.9-test'" 5 && result whats-new-told-on-update PASS || result whats-new-told-on-update FAIL "$(q "['whatsNewVersion'], d['whatsNewShown']")"
# once per version: checking again tells nothing new
ipc whatsNewCheck
sleep 1
[ "$(q "['whatsNewShown']")" = "9.9.9-test" ] && result whats-new-once-per-version PASS || result whats-new-once-per-version FAIL
# the notification carries a "See everything" action opening the shipped summary
grep -q "See everything" /work/shani/Services/WhatsNew.qml && [ -f /work/data/whats-new.md ] \
    && result whats-new-see-everything PASS || result whats-new-see-everything FAIL
printf '0.0.0-test\n' > /etc/shani-version
