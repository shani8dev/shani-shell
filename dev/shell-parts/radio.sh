# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=radio)
# ---- Media Player > Radio (Shortwave parity) against a stand-in radio-browser.info
#      (dev/fake-radio.py): popular, near you, a genre, a search; a station plays
#      (its stream heard as playing), is counted with the directory, kept as a favourite ----
rm -f /tmp/fake-radio-counted
ipc radioShow popular
waitfor "d['radioStations'] == ['Akashvani Pune', 'Bollywood Hits', 'Night Jazz']" 10 && result radio-popular PASS || result radio-popular FAIL "$(q "['radioStations'], d['radioShowing']")"
shot radio 0.3
ipc radioShow "genre:jazz"
waitfor "d['radioStations'] == ['Night Jazz']" 8 && result radio-genre PASS || result radio-genre FAIL "$(q "['radioStations']")"
ipc radioShow "search:bolly"
waitfor "d['radioStations'] == ['Bollywood Hits']" 8 && result radio-search PASS || result radio-search FAIL "$(q "['radioStations']")"
ipc radioPlay "Bollywood Hits"
waitfor "d['mediaPlayerPlaying'] and d['mediaName'] == 'Bollywood Hits'" 15 && result radio-plays PASS || result radio-plays FAIL "$(q "['mediaPlayerPlaying'], d['mediaName'], d['mediaFile']")"
for i in $(seq 1 20); do grep -q u-bolly /tmp/fake-radio-counted 2>/dev/null && break; sleep 0.25; done
grep -q u-bolly /tmp/fake-radio-counted 2>/dev/null && result radio-play-counted PASS || result radio-play-counted FAIL "$(cat /tmp/fake-radio-counted 2>&1)"
ipc radioFavourite "Bollywood Hits"; ipc radioShow favourites
waitfor "d['radioFavourites'] == ['Bollywood Hits'] and d['radioStations'] == ['Bollywood Hits']" 6 && result radio-favourite PASS || result radio-favourite FAIL "$(q "['radioFavourites'], d['radioStations']")"
ipc radioFavourite "Bollywood Hits"
ipc mediaClose; ipc closeAll
