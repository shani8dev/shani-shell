# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=ime-poll-rests)
# ---- two input methods (as ShaniOS ships: English + Hindi phonetic): the bar asks
#      fcitx5 for the method every 2 s while someone is active, and not at all
#      after 20 s without input (a key cannot have switched it) ----
if command -v fcitx5-remote >/dev/null && command -v strace >/dev/null; then
    P="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5"; mkdir -p "$P"; rm -f /tmp/fcitx5-profile.keep
    if [ -f "$P/profile" ]; then cp "$P/profile" /tmp/fcitx5-profile.keep; fi
    printf '[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=keyboard-us\n\n[Groups/0/Items/0]\nName=keyboard-us\nLayout=\n\n[Groups/0/Items/1]\nName=m17n_hi_itrans\nLayout=\n\n[GroupOrder]\n0=Default\n' > "$P/profile"
    # a fresh shell counts as active for its first 20 s (wtype's keys are no activity
    # to niri - a real key is): asked while active, then not at all
    stopshell "$(pgrep -o -x qs)"
    QS_ICON_THEME=$QS_ICON_THEME QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 qs -p /work/shani >>/work/out/logs/qs.log 2>&1 &
    i=0; until st >/dev/null 2>&1 || [ $i -ge 300 ]; do sleep 0.05; i=$((i+1)); done
    qpid=$(pgrep -o -x qs); sleep 2
    timeout 10 strace -f -qq -e trace=execve -p "$qpid" 2>/tmp/ime-active.txt
    active=$(grep -c 'fcitx5-remote' /tmp/ime-active.txt)
    sleep 15                                                    # 20 s without input by now
    timeout 10 strace -f -qq -e trace=execve -p "$qpid" 2>/tmp/ime-idle.txt
    idle=$(grep -c 'fcitx5-remote' /tmp/ime-idle.txt)
    [ "$idle" = 0 ] && [ "$active" -ge 3 ] && result ime-poll-rests-when-idle PASS "active 10 s: $active asks, idle 10 s: $idle" \
        || result ime-poll-rests-when-idle FAIL "active 10 s: $active asks (want 3+), idle 10 s: $idle (want 0)"
    if [ -f /tmp/fcitx5-profile.keep ]; then mv /tmp/fcitx5-profile.keep "$P/profile"; else rm -f "$P/profile"; fi
else
    result ime-poll-rests-when-idle SKIP "no fcitx5-remote or strace here"
fi
