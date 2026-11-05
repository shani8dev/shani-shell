# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=theme-fade)
# ---- the light/dark fade ------------------------------------------------------
# Flipping the style walks darkT over ~300 ms (sampled mid-fade here), then
# settles on the new palette; reduce motion makes it instant.
ipc setting darkMode false
waitfor "d['darkFade'] < 0.99 and d['darkFade'] > 0.01" 2 && result theme-fade-is-gradual PASS "$(q "['darkFade']")" \
    || result theme-fade-is-gradual FAIL "$(q "['darkFade']")"
waitfor "sum(int(d['bg'][i:i+2],16) for i in (1,3,5)) > 3*215" 3 && result theme-fade-settles-light PASS || result theme-fade-settles-light FAIL "$(q "['bg']")"
settings '{"reduceMotion": true}'
ipc setting darkMode true
waitfor "d['darkFade'] == 1" 2 && result theme-fade-reduce-motion-instant PASS || result theme-fade-reduce-motion-instant FAIL "$(q "['darkFade']")"
settings '{}'
ipc setting darkMode true
waitfor "sum(int(d['bg'][i:i+2],16) for i in (1,3,5)) < 3*30" 3 && result theme-fade-back-to-dark PASS || result theme-fade-back-to-dark FAIL "$(q "['bg']")"
