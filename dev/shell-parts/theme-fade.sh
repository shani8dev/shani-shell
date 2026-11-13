# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=theme-fade)
# ---- the light/dark fade ------------------------------------------------------
# Flipping the style walks darkT over ~300 ms through in-between values (the
# shell counts them: a poll for one mid-fade sample missed it on a busy machine),
# then settles on the new palette; reduce motion makes it instant.
ipc setting darkMode false
waitfor "d['darkFade'] == 0 and d['darkSteps'] >= 3" 3 && result theme-fade-is-gradual PASS "$(q "['darkSteps']") steps" \
    || result theme-fade-is-gradual FAIL "$(q "['darkFade'], d['darkSteps']")"
waitfor "sum(int(d['bg'][i:i+2],16) for i in (1,3,5)) > 3*215" 3 && result theme-fade-settles-light PASS || result theme-fade-settles-light FAIL "$(q "['bg']")"
settings '{"reduceMotion": true}'
ipc setting darkMode true
waitfor "d['darkFade'] == 1" 2 && result theme-fade-reduce-motion-instant PASS || result theme-fade-reduce-motion-instant FAIL "$(q "['darkFade']")"
settings '{}'
ipc setting darkMode true
waitfor "sum(int(d['bg'][i:i+2],16) for i in (1,3,5)) < 3*30" 3 && result theme-fade-back-to-dark PASS || result theme-fade-back-to-dark FAIL "$(q "['bg']")"
