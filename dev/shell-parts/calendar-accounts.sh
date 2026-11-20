# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=calendar-accounts)
# ---- Calendar > Online accounts (what GNOME Calendar was kept for), against a real
#      CalDAV server (Radicale, in the dev image): the account added with its
#      password, EDS finding its calendar, the calendar's event in the agenda ----
if command -v radicale >/dev/null; then
    R=/tmp/radicale; rm -rf $R; mkdir -p $R/collections
    printf 'asha:dav-pass\n' > $R/users
    printf '[server]\nhosts = 127.0.0.1:5232\n[auth]\ntype = htpasswd\nhtpasswd_filename = %s/users\nhtpasswd_encryption = plain\n[storage]\nfilesystem_folder = %s/collections\n' $R $R > $R/config
    radicale --config $R/config >$R/log 2>&1 & rpid=$!
    for i in $(seq 1 40); do curl -s -o /dev/null http://127.0.0.1:5232/ && break; sleep 0.25; done
    curl -s -u asha:dav-pass -X MKCALENDAR http://127.0.0.1:5232/asha/work/ >/dev/null
    t=$(date -d tomorrow +%Y%m%d)
    printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//shani//test//EN\r\nBEGIN:VEVENT\r\nUID:dav-1@shani\r\nDTSTAMP:%sT090000Z\r\nDTSTART:%sT100000Z\r\nDTEND:%sT110000Z\r\nSUMMARY:Planning on the server\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' $t $t $t \
        | curl -s -u asha:dav-pass -X PUT -H 'Content-Type: text/calendar' --data-binary @- http://127.0.0.1:5232/asha/work/dav-1.ics >/dev/null
    ipc calendarOpen; sleep 1
    # a wrong password: said, nothing added
    printf '%s' "wrong" > /tmp/cal-pw
    ipc calendarAccountAdd "Work" "http://127.0.0.1:5232/" "asha" /tmp/cal-pw
    waitfor "d['calendarAccountError'] != ''" 15 && [ "$(q "['calendarAccounts']")" = "[]" ] && result calendar-account-wrong-password PASS "$(q "['calendarAccountError']" | head -c 100)" \
        || result calendar-account-wrong-password FAIL "$(q "['calendarAccountError'], d['calendarAccounts']")"
    printf '%s' "dav-pass" > /tmp/cal-pw
    ipc calendarAccountAdd "Work" "http://127.0.0.1:5232/" "asha" /tmp/cal-pw
    # EDS finds the account's calendars in its own time (seconds to a minute)
    for i in $(seq 1 20); do ipc calendarAccounts; waitfor "any(a.startswith('Work:') and len(a) > 5 for a in d['calendarAccounts'])" 3 && break; done
    waitfor "any(a.startswith('Work:') and len(a) > 5 for a in d['calendarAccounts'])" 2 && result calendar-account-added PASS "$(q "['calendarAccounts']")" \
        || result calendar-account-added FAIL "$(q "['calendarAccounts'], d['calendarAccountError']")"
    # EDS fetches the calendar's events a moment after finding it
    for i in $(seq 1 20); do ipc calendarRefresh; waitfor "'Planning on the server' in d['agenda']" 3 && break; done
    waitfor "'Planning on the server' in d['agenda']" 2 && result calendar-account-events PASS || result calendar-account-events FAIL "$(q "['agenda'], d['calendarNames']")"
    shot calendar-accounts 0.3
    # an .ics opened with the Calendar (an invitation): its event added, its day shown
    t=$(date -d '+2 days' +%Y%m%d)
    printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//shani//test//EN\r\nBEGIN:VEVENT\r\nUID:invite-1@shani\r\nDTSTAMP:%sT090000Z\r\nDTSTART:%sT140000Z\r\nDTEND:%sT150000Z\r\nSUMMARY:Invitation from a file\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' $t $t $t > /tmp/invite.ics
    SHANI_QS_CONFIG=/work/shani python3 /work/bin/shani app calendar /tmp/invite.ics >/dev/null 2>&1
    waitfor "d['calendarImported'] == '1 events added' and 'Invitation from a file' in d['agenda']" 30 && result calendar-import-ics PASS || result calendar-import-ics FAIL "$(q "['calendarImported'], d['agenda']")"
    ipc closeAll; rm -f /tmp/invite.ics
    kill $rpid 2>/dev/null; ipc closeAll; rm -f /tmp/cal-pw
else
    result calendar-account-added SKIP "no radicale in this image"
fi
