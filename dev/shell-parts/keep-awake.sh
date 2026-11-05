# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=keep-awake)
# ---- apps keep the screen awake (org.freedesktop.ScreenSaver through the bridge) ------------
waitfor "not d['locked']" 4
settings '{"dimAfter": 0, "lockAfter": 3, "screenOffAfter": 0}'
python3 /work/dev/fake-inhibit.py Firefox video-playing > /tmp/inhibit.out 2>&1 &
ipid=$!
waitfor "d['keptAwakeBy'] == 'Firefox' and not d['idleStagesOn']" 5 && result keep-awake-asked PASS || result keep-awake-asked FAIL "$(q "['keptAwakeBy']") $(cat /tmp/inhibit.out)"
# the lock stage (3 s) does not come while the app holds it
sleep 6
[ "$(q "['locked']")" = False ] && result keep-awake-holds-the-lock PASS || result keep-awake-holds-the-lock FAIL
# a second app, then the first one leaves the bus without a word (killed): its hold goes with it
python3 /work/dev/fake-inhibit.py mpv "Playing a video" --release 2 >/dev/null 2>&1 &
mpid=$!
waitfor "d['keptAwakeBy'] == 'Firefox and mpv'" 4 && result keep-awake-two-apps PASS || result keep-awake-two-apps FAIL "$(q "['keptAwakeBy']")"
kill $ipid
waitfor "d['keptAwakeBy'] == 'mpv'" 4 && result keep-awake-released-when-app-leaves PASS || result keep-awake-released-when-app-leaves FAIL "$(q "['keptAwakeBy']")"
# mpv says UnInhibit itself (and stays running): nothing holds it, and idle locks again
waitfor "d['keptAwakeBy'] == '' and d['idleStagesOn']" 5 && waitfor "d['locked']" 10 \
    && result keep-awake-uninhibit-then-idle-locks PASS || result keep-awake-uninhibit-then-idle-locks FAIL "$(q "['keptAwakeBy'], d['locked']")"
# GetActive: the lock screen is up
[ "$(gdbus call --session -d org.freedesktop.ScreenSaver -o /org/freedesktop/ScreenSaver -m org.freedesktop.ScreenSaver.GetActive 2>&1)" = "(true,)" ] \
    && result screensaver-get-active PASS || result screensaver-get-active FAIL
kill $mpid 2>/dev/null
settings '{}'
wtype "shani-test" -k Return
waitfor "not d['locked']" 6
