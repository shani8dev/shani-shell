# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=window-look)
# ---- how windows look and move: Settings > Windows > Look and motion ----------------------
# Services/WindowLook writes ~/.config/niri/shani-look.kdl (the open and close
# shaders, speed, shadow, corners, blur). Each style: niri loads it (nothing put
# back), compiles its shaders (nothing in niri's log), and a window caught
# halfway through opening and closing - slowed right down - is photographed.
LOOK=/root/.config/niri/shani-look.kdl
NLOG=/work/out/logs/niri.log
for style in glide pop dissolve plain; do
    undone=$(q "['niriConfigUndone']")
    lines=$(wc -l < "$NLOG")
    settings "{\"winMotion\": \"$style\", \"winSpeed\": 12, \"winShadow\": \"deep\", \"winCorners\": 18, \"blurStrength\": \"strong\"}"
    i=0; until grep -q "slowdown 12.00" "$LOOK" 2>/dev/null && { [ "$style" = plain ] || grep -q "custom-shader" "$LOOK"; } || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
    sleep 1.5
    [ "$(q "['niriConfigUndone']")" = "$undone" ] && grep -q "geometry-corner-radius 18" "$LOOK" \
        && result "look-$style-loads" PASS || result "look-$style-loads" FAIL "undone $(q "['niriConfigUndone']") (was $undone); $(tail -n +$((lines + 1)) "$NLOG" | grep -i -E "error|warn" | tail -1 | cut -c1-200)"
    ipc closeAll; sleep 0.5
    grim "$SHOTS/look-$style-before.png"
    foot -a shani-look -T "Look $style" sh -c 'printf "\033[1;38;5;209m  %s\033[0m\n\n" "Windows that open beautifully"; ls -l --color=always /usr/bin | head -40; sleep 60' >/dev/null 2>&1 &
    for f in 1 2 3 4; do sleep 0.7; grim "$SHOTS/look-$style-open-$f.png"; done
    sleep 3; grim "$SHOTS/look-$style-open.png"
    # the window is there in the end
    niri msg -j windows | grep -q "\"Look $style\"" && result "look-$style-window-shows" PASS || result "look-$style-window-shows" FAIL "no window titled Look $style"
    niri msg action close-window
    for f in 1 2 3; do sleep 0.6; grim "$SHOTS/look-$style-close-$f.png"; done
    sleep 3; pkill -f "Look $style" 2>/dev/null
    errs=$(tail -n +$((lines + 1)) "$NLOG" | grep -i -E "shader|glsl|compil" | grep -i -E "error|fail" | head -1 | cut -c1-220)
    [ -z "$errs" ] && result "look-$style-shaders-compile" PASS || result "look-$style-shaders-compile" FAIL "$errs"
done
# animations off (Reduce motion): the file says so, and no shader is left in it
settings '{"reduceMotion": true}'
i=0; until grep -q "^    off" "$LOOK" 2>/dev/null || [ $i -ge 20 ]; do sleep 0.25; i=$((i+1)); done
grep -q "^    off" "$LOOK" && ! grep -q custom-shader "$LOOK" && result look-reduce-motion-stops-animations PASS || result look-reduce-motion-stops-animations FAIL "$(head -5 "$LOOK" | tr '\n' ';')"
settings '{}'
sleep 1.5
