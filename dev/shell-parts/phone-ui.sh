# Run at both 412×915 and 915×412 with SHANI_FORM_FACTOR=phone.
waitfor "d['formFactor'] == 'phone' and d['layoutPreset'] == 'phone'" 15 \
    && result phone-ui-profile PASS || result phone-ui-profile FAIL

ipc dismissAll
ipc layoutUse phone
if waitfor "d['layoutSwitcher'] and d['layoutTrying'] == 'phone'" 8; then
    shot phone-layout-switcher
    wtype -k Return
    waitfor "not d['layoutSwitcher'] and d['layoutPreset'] == 'phone'" 8 \
        && result phone-ui-layout-confirm PASS || result phone-ui-layout-confirm FAIL
else
    result phone-ui-layout-confirm FAIL "layout picker did not open"
fi

ipc windowLayoutsToggle
waitfor "d['windowLayouts']" 5 && result phone-ui-window-layouts PASS || result phone-ui-window-layouts FAIL
shot phone-window-layouts
ipc closeAll

ipc tour
waitfor "d['tour']" 5 && result phone-ui-tour PASS || result phone-ui-tour FAIL
shot phone-tour
wtype -k Right
shot phone-tour-quick-settings
ipc closeAll

ipc toggleControlCenter
waitfor "d['controlCenter']" 5 && result phone-ui-quick-settings PASS || result phone-ui-quick-settings FAIL
shot phone-quick-settings
ipc closeAll

ipc settings
waitfor "d['settingsOpen'] and not d['dockShown']" 8 \
    && result phone-ui-app-hides-favorites PASS || result phone-ui-app-hides-favorites FAIL
shot phone-settings
ipc closeAll
waitfor "d['dockShown']" 8 && result phone-ui-favorites-return-home PASS || result phone-ui-favorites-return-home FAIL

errors=$(grep -aE '(LayoutSwitcher|WindowLayouts|Modules/Tour|Modules/Settings/Settings(Look|Page)|Modules/ControlCenter/).*([Ee]rror:|Binding loop|Unable to assign)' /work/out/logs/qs.log || true)
[ -z "$errors" ] && result phone-ui-no-layout-errors PASS || result phone-ui-no-layout-errors FAIL "$errors"
