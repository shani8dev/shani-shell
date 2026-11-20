# Combined surface coverage (render + shell suite)

Two harnesses photograph the shell, and neither alone is the full picture:

- **`dev/render.sh`** (this repo's `render=shell|setup|greeter|all`) stages clean,
  full-window "beauty" shots in `out/renders/`, each behind a state assertion.
- **`dev/shell-test.sh` + `dev/shell-parts/*.sh`** take evidence shots during
  behavioural tests in `out/shots/`; `check.sh a11y` walks the same surfaces
  through AT-SPI.

Combined they cover **261 distinct surfaces**
(60 render-only, 178 shell-suite-only, 23 in both).

## In both harnesses (23)
annotate, app-, bt-passkey, captions, desktop-widgets, display-confirm, dock-menu, island-approval, launcher-apps, launcher-calc, launcher-full, layout-switcher, lock-wrong, magnifier, notification-popup, osd-volume, processes, ring-sub, screensaver, settings-, share-sheet, tour, writing-tools

## Only in the render harness (60)
assistive-touch, bt-pair-confirm, cc-main, chronoa-panel-idle, chronoa-panel-speaking, chronoa-panel-thinking, desktop-dark, desktop-light, desktop-rest, flash-alert, greeter-auth-failed, greeter-login, greeter-otp-code, island-ask, island-caffeine, island-dnd, island-media, island-record, island-rest, island-timer, island-working, launcher-actions, launcher-clipboard, launcher-convert, launcher-emoji, launcher-empty, launcher-files, lens-ready, lock-screen, media-library, media-live-tv, media-playing, media-radio, modem-call, modem-sms-composer, notification-actions, notification-critical, notification-dnd, notification-sms, osd-brightness-down, osd-brightness-up, osd-mic-mute, osd-mute, osd-volume-down, osk-language, osk-main, overview-open, overview-search, qr-code, quick-look, ring-at-point, ring-main, ruler, settings-main, settings-search-empty, settings-search-empty-folders, settings-search-proxy, switcher-open, wallpaper-style, whats-new

## Only in the shell suite (178)
accent-orange, accessibility, agenda, ambient-osd, app-archives-zip, app-authenticator-codes, app-clocks-stopwatch, app-containers, app-converter-list, app-media-player-audio, app-media-player-library, app-media-player-song, app-media-player-video, app-nearby-offer, app-passwords, app-permissions, app-photos-grid, app-software, app-software-page, app-tasks-list, archive-compress, archive-password, bluetooth-push, board-bar, board-whiteboard, breakpoints-launcher, breakpoints-quick-settings, breakpoints-settings-categories, breakpoints-settings-page, bt-pair, calendar-accounts, call-record, call-ringing, caps-lock-osd, charging, clipboard-from-phone, clipboard-image, control-centre, desktop-icons, diskusage-dupes, dock-badge, dock-progress, dock-stepped-aside, dock-workspaces, document-night, documents-, documents-form, documents-zoomed, file-actions, files-all-pictures, files-cloud, files-compare, files-copy-history, files-copy-paused, files-devices, files-job, files-lock, files-properties, files-tabs, files-thumbs, files-unlock, files-usb-write, flash, floating-workspace, fonts-file, form-factor-tv-launcher, handheld-quick-panel, input-method, inputplumber-quick-settings, inputplumber-settings, island-activity, launcher-by-meaning, launcher-file, launcher-providers, layout-classic, lens, light-desktop, light-sidebar, lights, live-wallpaper, lock, lock-camera, maps-online-place, maps-online-route, maps-place, maps-route, maps-saved, media-mini, media-resumed, media-song-cover, media-subtitles, mic-in-use, mixer, network-home-zone, notification-cards, osk-controller, osk-dictating, osk-marathi, osk-russian, osk-tamil, osk-typed, overview, overview-card, pad-tour-field-keyboard, pad-tour-launcher, pad-tour-lock, pad-tour-notification, pad-tour-overview, pdf-password, phone-bar, phone-launcher, phone-lock, phone-notification, phone-quick-settings, photo-countdown, popup-bottom, power-limit, printers-add, qr, quicklook-, quicklook-from-files, radio, remote-desktop, remote-keyboard, ring, ring-at-bubble, saved-networks, screenshot-offer, settings, settings-about, settings-account, settings-apps, settings-backup, settings-battery, settings-categories, settings-date-language, settings-displays, settings-input, settings-layouts, settings-look, settings-personal-colours, settings-privacy, settings-screen-time, settings-sharing-nearby, settings-shortcuts, settings-sound, settings-storage, settings-terminal, sidebar, sidebar-shelf, sidebar-tiles-mic, smart-island, smart-replies, smart-replies-real, smart-touch, sms, start-hints, switcher, tablet-quick-settings, terminal-foot-dark, terminal-foot-light, terminal-foot-new-light, tidy-plan, tiles-editing, touch-layout-editor, touch-layout-keyboard, tour-make-it-yours, transcribe, tv-home, ups-settings, users-page, viewer-edit, viewer-marks, viewer-markup, wake-sources, window-menu, window-menu-app-menus, writing-tools-real

## Not photographable here
- `file picker` — layer-shell Overlay that the nested niri does not composite;
  driven by the shell suite's state assertions instead.
- `window menu`, `whiteboard`, `quick panel`, `TV home`, `charging FX`,
  `file-actions card` — Overlay panels the shell suite already photographs
  (`44-window-menu`, `board-whiteboard`, `handheld-quick-panel`, `tv-home`,
  `26h-charging`, `26j-file-actions`), so the render harness does not duplicate them.
- `scratchpad terminal` / `AI console` — external app windows, not shell QML.

## Keeping this in sync
Both lists are derived from the source (`capture`/`shot` calls), not hand-written,
so a new surface appears here automatically when its harness gets a capture.
The guard in `tests/test_cli_ipc_wiring.py` checks that every render IPC resolves
to a real shell function and every `want` names a real `state()` key.
