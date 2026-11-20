# ---- Media Player > Live TV (Hypnotix-style M3U channels) -------------------------
# No real streams: the playlist points at a dead local port, but the whole path
# from a playlist to a channel in the player is exercised.
cat > /tmp/live-tv-test.m3u <<'EOF'
#EXTM3U
#EXTINF:-1 tvg-id="test-news" group-title="News",Test News
http://127.0.0.1:59999/news.m3u8
#EXTINF:-1 group-title="Movies",Test Movie
http://127.0.0.1:59999/movie.m3u8
EOF
ipc liveTvLoad /tmp/live-tv-test.m3u
waitfor "len(d['liveTvChannels']) == 2 and 'Test News' in d['liveTvChannels']" 8 \
    && result live-tv-loads-channels PASS "$(q "['liveTvChannels']")" \
    || result live-tv-loads-channels FAIL "$(q "['liveTvChannels'], d['liveTvError']")"
waitfor "'News' in d['liveTvGroups'] and 'Movies' in d['liveTvGroups']" 4 \
    && result live-tv-groups PASS "$(q "['liveTvGroups']")" \
    || result live-tv-groups FAIL "$(q "['liveTvGroups']")"
ipc liveTvGroup News
waitfor "d['liveTvShown'] == 1" 4 \
    && result live-tv-group-filters PASS || result live-tv-group-filters FAIL "$(q "['liveTvShown']")"
ipc liveTvPlay "Test News"
waitfor "d['mediaFile'].endswith('/news.m3u8')" 5 \
    && result live-tv-plays-a-channel PASS "$(q "['mediaFile']")" \
    || result live-tv-plays-a-channel FAIL "$(q "['mediaFile'], d['mediaError']")"
ipc liveTvLoad defaults
waitfor "len(d['liveTvChannels']) >= 100" 8 \
    && result live-tv-free-picks PASS || result live-tv-free-picks FAIL "$(q "['liveTvChannels'], d['liveTvError']")"
# a playlist with no channels says so instead of showing an empty list silently
printf '#EXTM3U\n# nothing here\n' > /tmp/live-tv-empty.m3u
ipc liveTvLoad /tmp/live-tv-empty.m3u
waitfor "d['liveTvError'] != ''" 6 \
    && result live-tv-empty-playlist-is-honest PASS || result live-tv-empty-playlist-is-honest FAIL "$(q "['liveTvError']")"
ipc closeAll; rm -f /tmp/live-tv-test.m3u /tmp/live-tv-empty.m3u
