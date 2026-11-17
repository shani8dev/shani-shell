# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=form-factor)
# ---- the kind of screen and the size of everything on it (docs/FORM-FACTORS.md) ----
# Services/FormFactor over Common/FormFactor.js (whose rules tests/test_form_factor.py
# checks): the dev session's screen (niri's nested "winit", which reports no size)
# is a computer at scale 1; the owner's choice for it in Settings > Displays turns
# it into a TV at once, everything 1.6 times larger, and Automatic puts it back.
# (Not under SHANI_FORM_FACTOR, which sets every screen and is what this checks against.)
if [ -z "${SHANI_FORM_FACTOR:-}" ]; then
    waitfor "d['formFactor'] != ''" 4
    [ "$(q "['formFactor']")" = computer ] && [ "$(q "['uiScale'] == 1")" = True ] \
        && result form-factor-computer-by-default PASS || result form-factor-computer-by-default FAIL "$(q "['formFactor'], d['uiScale'], d['formFactors']")"
    settings '{"formFactors": {"winit": "tv"}}'
    waitfor "d['formFactor'] == 'tv' and abs(d['uiScale'] - 1.6) < 0.01" 5 \
        && result form-factor-chosen-tv-scales-everything PASS "$(q "['uiScale']")" || result form-factor-chosen-tv-scales-everything FAIL "$(q "['formFactor'], d['uiScale']")"
    ipc toggleLauncher; sleep 1.2; shot form-factor-tv-launcher 0.2; ipc closeAll
    settings '{"formFactors":{"winit":"tv"},"formFactorScales":{"winit":1.25}}'
    waitfor "d['formFactor'] == 'tv' and abs(d['uiScale'] - 1.25) < 0.01" 5 \
        && result form-factor-shell-size-override PASS || result form-factor-shell-size-override FAIL
    settings '{"formFactors":{"winit":"tv"},"formFactorScales":{"winit":9}}'
    waitfor "abs(d['uiScale'] - 1.6) < 0.01" 5 \
        && result form-factor-invalid-shell-size-ignored PASS || result form-factor-invalid-shell-size-ignored FAIL
    settings '{}'
    waitfor "d['formFactor'] == 'computer' and d['uiScale'] == 1" 5 \
        && result form-factor-automatic-again PASS || result form-factor-automatic-again FAIL "$(q "['formFactor'], d['uiScale']")"
fi
