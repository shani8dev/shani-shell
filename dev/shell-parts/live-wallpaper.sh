# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=live-wallpaper)
# ---- live wallpaper: plays only while it can be seen ----
V=/root/Videos/Wallpapers; mkdir -p $V
ffmpeg -loglevel error -f lavfi -i "mandelbrot=size=640x360:rate=15" -t 8 -pix_fmt yuv420p -c:v libx264 -preset ultrafast $V/waves.mp4 2>/dev/null
out=$(niri msg -j outputs | python3 -c "import json,sys; print(next(iter(json.load(sys.stdin))))")
playing() { q "['liveWallpaperPlaying'].get('$out')"; }
why() { q "['liveWallpaperWhy'].get('$out')"; }
settings "{\"wallpaperVideo\": \"$V/waves.mp4\", \"wallpaperVideoOnBattery\": true}"
waitfor "d['liveWallpaperPlaying'].get('$out') == True" 10 && result live-wallpaper-plays PASS || result live-wallpaper-plays FAIL "playing $(playing), why '$(why)'"
sleep 1.5; shot live-wallpaper 0.2
foot -a lwcover sh -c 'sleep 30' >/dev/null 2>&1 &
waitfor "d['liveWallpaperWhy'].get('$out') == 'covered' and d['liveWallpaperPlaying'].get('$out') == False" 8 \
    && result live-wallpaper-pauses-under-windows PASS || result live-wallpaper-pauses-under-windows FAIL "playing $(playing), why '$(why)'"
pkill -f lwcover
waitfor "d['liveWallpaperPlaying'].get('$out') == True" 8 && result live-wallpaper-resumes PASS || result live-wallpaper-resumes FAIL "playing $(playing), why '$(why)'"
# on battery as the shell sees it (Power.onBattery, what LiveWallpaper reads) - not
# upower's battery state, which said "discharging" while the shell's OnBattery was
# false (a laptop on battery, in the container), and failed a check that never applied
if [ "$(q "['onBattery']" 2>/dev/null)" = True ]; then
    settings "{\"wallpaperVideo\": \"$V/waves.mp4\", \"wallpaperVideoOnBattery\": false}"
    waitfor "d['liveWallpaperWhy'].get('$out') == 'battery' and d['liveWallpaperPlaying'].get('$out') == False" 8 \
        && result live-wallpaper-pauses-on-battery PASS || result live-wallpaper-pauses-on-battery FAIL "playing $(playing), why '$(why)'"
else
    result live-wallpaper-pauses-on-battery SKIP "this machine is on mains power"
fi
settings '{}'
waitfor "d['liveWallpaperWhy'].get('$out') == 'off'" 6 && result live-wallpaper-off PASS || result live-wallpaper-off FAIL "why '$(why)'"
