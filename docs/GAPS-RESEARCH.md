# Research archive — full gap reports

`docs/GAPS.md` is the curated, deduplicated gap list. This file preserves the
**complete reports from the research agents** so nothing is lost to
summarisation. Each section is the agent's report with only formatting
normalised. Static findings only — no runtime/hardware verification.

---

# Seventh pass — regional formats, file formats, disability a11y, web, sandbox, help, other desktops

## Regional and locale format depth (agent ses_dfbd947ceffeNYnkLlhJkCIAGY)

**Core finding:** `Common/Tr.qml` follows `locale.conf` live for *words*, but no
`QLocale.setDefault` and no locale argument to `Qt.formatDate`/`Qt.formatTime`
exists anywhere in the tree (verified by grep: only `Qt.locale()` in
`SettingsDateLanguage.qml:35` and `Radio.qml:77`). The format preview in Settings
(`SettingsDateLanguage.qml:244-247`, `date "+%A, %x"`, `printf "%'.2f"`) promises
grouped, locale-ordered output that no app actually renders.

1. **Dates ignore QLocale.** Every `Qt.formatDate(d,"d MMM")` uses the process-default locale (C/English at startup), never `Tr.lang`. `Services/Files.qml:1608-09`, `Services/Feeds.qml:103`, `Services/Mail.qml:39`, `Services/Agenda.qml:189`, `Services/Backup.qml:59`, `Services/QuickLook.qml:101`. Sketch: pass `Qt.locale(Tr.chosen||undefined)` as `Qt.formatDate`'s third arg.
2. **12/24h toggle ignored in 9+ surfaces.** `use24h` is honoured in Bar/Link/Clocks but not `Services/Feeds.qml:102`, `Services/Mail.qml:38`, `Services/Files.qml:1606`, `Services/Agenda.qml:189-190,240,265`, `Services/Backup.qml:59`, `Services/QuickLook.qml:101`, `Services/WorldClock.qml:80`, `CalendarPanel.qml:67,74,184,208,265` (always `HH:mm`). Sketch: gate each on `Settings.data.use24h`.
3. **Hardcoded English weekday/month arrays.** `Services/Weather.qml:166` `["Sun"…]`; `Common/DatePicker.qml:21`, `Modules/ControlCenter/Calendar.qml:42`, `Modules/Calendar/CalendarPanel.qml:128` `["Su","Mo"…]`. Sketch: `Qt.locale().dayName(i,QLocale.ShortFormat)` / `Qt.formatDate(d,"ddd")`.
4. **Fixed day-month order in all short dates.** Even with a real QLocale, `"d MMM"` forces day-first; en-US expects month-first. Same files as #1. Sketch: `Qt.formatDate(d, Qt.locale().dateFormat(QLocale.ShortFormat))`.
5. **File sizes mislabel binary bytes.** `Services/Files.qml:1591-95`, `Services/ObexReceive.qml:19`, `Services/FileActions.qml:101` divide by 1024 but print `KB/MB/GB`. Sketch: `KiB/MiB/GiB` (or decimal /1000).
6. **No number grouping / digit script / Indian grouping.** Numbers use JS `toFixed`/`toString` with `.` and ASCII digits: `Files.qml:1593-95`, `Services/Displays.qml:83`, Calculator display. No `toLocaleString`; no Devanagari numerals; no १,००० / 1,00,000. Sketch: `Number(x).toLocaleString(Qt.locale())`.
7. **AM/PM not localised or missing.** `"h:mm AP"` yields English AM/PM from QLocale; `Modules/ScreenSaver/Cover.qml:85`, `QuickPanel.qml:108`, `TvHome.qml:137` use `"h:mm"` with **no** AP → ambiguous 12-hour time. Sketch: include AP and use `Qt.locale().amText/pmText`.
8. **First day of week is monday|sunday only, not locale-derived.** `Common/Settings.qml:185`; applied in `DatePicker.qml:18`, both Calendars. Locales starting Saturday unreachable. Sketch: default from `Qt.locale().firstDayOfWeek`.
9. **ISO week numbering hardcoded.** `CalendarPanel.qml:31,117` (`isoWeek()`), `SettingsDateLanguage.qml:357-58` says "ISO weeks". Locale week-1 rules (US: week containing Jan 1) absent. Sketch: use QLocale/QCalendar week rules.
10. **Weather's imperial toggle is temperature-only.** `WeatherWindow.qml:186,188,259` always `km/h` and `km`; `Services/Weather.qml:183` requests only `temperature_unit`. Sketch: send `wind_speed_unit=mph` and pick `mph`/`mi` from `weatherUnits`.
11. **Maps distance always metric.** `MapsWindow.qml:116` `km()`/`m` hardcoded, no toggle. `SettingsDateLanguage.qml:237` writes `LC_MEASUREMENT`, but no app reads it. Sketch: reuse `Calc.js` unit table with a metric/imperial setting.
12. **No real currency conversion.** `Launcher/Calc.js:89-92` detects `100 USD in INR` but hands it to Chronoa LLM (`Launcher.qml:365-366`); Calculator converter tab has only physical units (`Calculator.qml:73`, `Calc.js:61-71`). No rates, symbols, or locale placement. Sketch: small rates bridge + `Qt.locale().currencySymbol`.
13. **Collation is codepoint/lowercase, not locale-aware.** `bridge/files.py:335-366` (`natural_key`, `name.lower()`), `bridge/contacts.py:130-135` (`sort_key`) sort Indic/accented names wrong; QML uses `localeCompare` with no locale (`Viewer.qml:361`, `Launcher.qml:288`, `AppPicker.qml:103`, `MusicLibrary.qml:39`). Sketch: `localeCompare(b, Qt.locale().name)` / Python `locale.strxfrm`.
14. **Locale setup: formats written but never consumed.** `SettingsDateLanguage.qml:235-240` writes LC_TIME/NUMERIC/MONETARY/MEASUREMENT/PAPER; `:324` claims "every language is installed"; but only hi.json/mr.json ship and QML formatters ignore all LC_*; change needs re-login (`:327`). Sketch: wire `Qt.locale()` from the chosen locale, or state the preview is illustrative.
15. **First-boot wizard sets LANG only.** `bridge/first-account.py:133` `localectl set-locale LANG=…`; no format/measurement choices. Sketch: add a format-locale page that writes LC_* too.
16. **Per-event timezone is display-only.** `CalendarPanel.qml:67,74` falls back to local time for unsupported zones. Sketch: use ICU/i18n timezone conversion for event rendering.
17. **No alternate calendars.** Calendar is Gregorian-only (`CalendarPanel.qml:87-92` JS Date arithmetic); Kundali hardcodes Lahiri ayanamsa. No Vikram Samvat/Hijri for Marathi/Hindi dates. Sketch: surface QCalendar/ICU calendar types behind a setting.
18. **Percent/sign spacing hardcoded.** `Services/Plugged.qml:92` `Tr.t("Battery %1 %", b)` — fixed space, no locale percent sign/placement. Sketch: `Qt.locale().percent()`-aware formatting.

Highest value × ease: #1–#5, #7, #10. Needs design: #12, #17. Risk: no runtime/locale data available to verify Qt produces Marathi/Hindi month names on this image.

## File-format compatibility matrix (agent ses_dfbd91e06ffeLTNYXfM5zIXwP5)

Audited `bin/shani:425-586`, skel `mimeapps.list`, each bridge/QML decoder path, and the PKGBUILD. "FP" = Flatpak fallback exists.

1. **Text Editor ships zero syntax grammars.** `TextMate.qml:16-20` scans `~/.local/share/shani-textmate` and `/usr/share/shani-shell/textmate`; `*.tmLanguage` count = 0, PKGBUILD installs none. Every file falls back to regex highlighter (`TextEditorPanel.qml:224`). Sketch: vendor ~5 small grammars (C/Py/QML/JS/JSON). FP yes.
2. **UTF-16 text is classified "Not a text file".** `TextDocs.qml:143` uses `grep -qI ""`; any NUL-bearing file (UTF-16/32) tests binary and is refused before FileView (`:179-195`) can decode a BOM. Latin-1 has no selector. Sketch: BOM sniff in the probe, decode via a bridge with explicit codec. FP yes.
3. **Viewer's navigation list narrower than its MIME claims.** `Viewer.qml:37-39` `isImage()` accepts only 13 extensions; `bin/shani:438` claims JXL, PSD, TGA, PCX, EXR, HDR, DDS, QOI, PPM/PGM/PBM/PAM, XPM, XBM, ICO — all decodable via kimageformats per PKGBUILD:35-40 — but they vanish from next/prev (`:360`). Sketch: derive `isImage()` from the claimed MIME set. FP yes.
4. **Photos grid excludes formats its importer accepts.** `PhotosWindow.qml:113` scans only jpg/jpeg/png/webp/gif/avif/bmp; import picker at `:285` offers heic/heif. Imported HEIC never appears. TIFF/raw absent. Sketch: extend the `find` filter. FP yes.
5. **QuickLook's format table lags every app.** `QuickLook.qml:28-36`: no heic/jxl/psd/raw in image, no epub/djvu/cbz in pdf, no deb/apk/rpm in archive, no aiff/wma in audio. Sketch: reuse the APPS MIME table. FP partial.
6. **OPML round-trip destroys feed categories.** `feeds.py:475-485` writes flat outlines with only text/title/xmlUrl; `:502-509` reads only xmlUrl. Tags are first-class in feeds.json (`:273,348-364`) and drive UI filters (FeedsWindow.qml:50-77). Sketch: emit/read `category=`. FP no.
7. **RPM offered in Archive picker but unreadable.** `Archive.qml:54` includes rpm in types used by ArchivesWindow.qml:20; bin/shani:478-488 and mimeapps.list omit application/x-rpm; libarchive/bsdtar has no RPM reader. Sketch: drop rpm, or `rpm2cpio | bsdtar -x`. FP yes.
8. **Office documents have no shell path at all.** No DOCX/ODT/PPTX/XLSX MIME in bin/shani; only an icon (DesktopIcons.qml:65), tidy category (tidy.py:32), defaults to OnlyOffice Flatpak (mimeapps.list:295-389). `pymupdf.office.to_pdf()` exists but needs a separate licensed package. Sketch: read-only PDF-render bridge or accept the Flatpak explicitly. FP yes.
9. **Mail cannot open local .eml, mbox, Maildir or MSG.** `mail.py:6,17` is IMAP/SMTP/MailHog only; MailWindow.qml:20-26 uses FilePicker solely to save attachments. message/rfc822 unregistered. Sketch: `open <path>` via email.parser plus MIME registration. FP yes.
10. **Media Player claims ~130 MIME types with no capability probe.** bin/shani:446-471 + mimeapps.list:409-507 default MIDI, DTS-HD, Amiga modules, RealAudio, niche video to a thin MediaPlayer{} forwarding to QtMultimedia's FFmpeg backend. Only failure surface is generic onErrorOccurred (:246). Sketch: probe `ffmpeg -decoders/-formats` once and narrow defaults. FP yes.
11. **Converter input sets much narrower than player's.** convert.py:40-81 omits .mts/.m2ts/.vob/.3g2/.f4v/.rmvb and all documents, so PDFs/e-books cannot be converted. Sketch: extend VIDEO_IN/AUDIO_IN. FP partial.
12. **Converter output codecs hardcoded, quality 3 presets.** convert.py:82-92,144-196 emits only libx264/libvpx-vp9 and 3 CRF/bitrate tuples, no HEVC/AV1/10-bit/HDR; UI offers only Small/Balanced/Best. Sketch: expose codec + numeric CRF. FP yes.
13. **DjVu/PS/EPS defaults depend on optional tools.** PdfViewer.qml:283-298 requires ddjvu and gs; PKGBUILD lists djvulibre/ghostscript as optdepends, yet bin/shani:441-445 claims the MIME types unconditionally. Sketch: make them hard deps or gate the claim. FP yes.
14. **Calendar registers vCalendar but imports only VEVENT.** bin/shani:551 claims application/x-vcalendar; agenda.py:601-619 walks VEVENT_COMPONENT only, so VTODO/VJOURNAL in .ics/.vcs are dropped. Sketch: route VTODO to Tasks. FP no.
15. **Multipage TIFF shows only page 1.** Viewer.qml:169 converts with `magick "$1[0]"`; display is AnimatedImage (`:92-100`) with no page navigation. Sketch: render `[N]` pages like the PDF strip. FP yes.
16. **E-book/comic conversion has no test.** pdfform.py:124-137 topdf() is the single failure point for EPUB/FB2/MOBI/XPS/CBZ; no test mentions them. Sketch: one fixture per format. FP yes.
17. **QuickLook treats any extensionless file under 2 MB as text.** QuickLook.qml:103-104 only checks size, then heads it; binaries render as garbage. Sketch: sniff first bytes. FP no.
18. **Archive creation supports 4 formats despite reading 20.** Archive.qml:261 offers only zip/tar.gz/tar.xz/7z; .tar.zst/.tar.bz2/.cab readable but not creatable. FP yes.

Cross-cutting: the real matrix is 3 hard deps (kimageformats, qt6-multimedia-ffmpeg, python-pymupdf+libarchive) wrapped in a 130-entry MIME list asserted, never measured. Cheapest systemic fix: one startup capability probe filtering MimeType claims against installed decoders.

## Accessibility by disability group (agent ses_dfbd8f957ffelb4UVc8c7xANEO)

1. **High contrast stops at the shell** (low vision). Toggle only swaps Theme tokens; GTK/libadwaita apps set to adw-gtk3; Access.qml:28-34 pushes only screen-reader + text-scaling to gsettings. Sketch: also set org.gnome.desktop.a11y.interface high-contrast and a real HC GTK theme.
2. **Flash alerts die at the lock screen** (deaf). Incoming calls urgency-2 always alert, but FlashAlert.qml:25 returns while locked. Sketch: let overlay flash run over WlSessionLock, or render a persistent visual call card there.
3. **Braille stack ships but is inert** (blind). shani-accessibility PKGBUILD:8-12 depends on brltty/espeakup but no .install enables either; /var/lib/brltty bind-mounted but nothing starts; Plugged.qml:143-146 only flips Orca. Sketch: enable brltty/espeakup units; Braille subsection.
4. **TTS has no voice/language/pitch choice** (blind/speech). Speak.qml:20,24-25 only three speed chips; rate line hardcodes spd-say/espeak args. Sketch: list voices and expose voice + pitch.
5. **Voice typing ≠ voice control** (motor). Dictation.qml:26-65 transcribes and types via wtype; no spoken-command grammar. Sketch: classify transcript as command vs dictation before typing.
6. **No switch access** (motor). GamepadNav.qml:1-15 d-pad/stick/buttons; OSK supports arrow+OK but nothing scans from a single switch. Sketch: timed linear scan driven by any bound key/button with adjustable speed.
7. **Orca is fire-and-forget** (blind). Access.qml:18-27 launches `orca --replace` and probes command -v; no AT-SPI env assertion, no preferences entry, no describe-surface command. Sketch: set QT_ACCESSIBILITY=1/GTK_MODULES=gail:atk-bridge; add Orca prefs + describe IPC.
8. **Captions have no call source or speaker labels** (deaf). Captions.qml:15-18,42-48 only speakers/mic via pw-record. Sketch: third source bound to active call PipeWire node plus speaker labels.
9. **Non-visual notifications are title-only and inert** (blind). Speak.qml:20,38-43 speaks app+summary, never body; no spoken reply/dismiss; hard 2000-char cap. Sketch: add read-body and map actions to spoken commands.
10. **Magnifier is pointer-only** (low vision). Magnifier.qml:73-84 lens follows MouseArea; no focus-follow. Sketch: focus-follow mode reading Niri.focusedWindow geometry.
11. **No simple/essential mode** (cognitive). SettingsPage.qml:1305-1377 has no such row. Sketch: toggle hiding advanced tiles/pages, large targets, icon+text labels.
12. **No reading assistance / text-only mode** (cognitive/low vision). Speak.qml:28,45-50 select-to-speech is sole aid. Sketch: global reading overlay with line highlight and font override.
13. **Dictation language borrowed from OSK/captions** (speech). Dictation.qml:19-25 only auto/en/mr/hi. Sketch: separate picker reusing installed Whisper models; show confirmation before typing.
14. **Audio-description tracks unidentified** (blind/low vision). MediaPlayerWindow.qml:553-559,116-119 render by title/language only. Sketch: flag AD track titles and offer dual-track mix.
15. **Distraction-free is notifications-only** (cognitive). Focus.qml:1-5,20-25 holds notifications; bar/dock stay. Sketch: hide non-essential bar chips and dim dock.
16. **No global "always show labels" setting.** Chip.qml:24-26 carries label + Accessible name but dense states are glyph-only. Sketch: accessibility setting forcing visible labels.

Low-effort: #1 is a gsettings line; #4/#13/#15/#16 single rows. Real work: #3/#5/#6/#8. Out of scope: colour filters/HDR/gamma (niri), dwell/eye-pointer (no pointer position), Sticky/Slow/Bounce Keys (compositor), native Wayland Qt6/Chromium AT-SPI menus (no appmenu protocol).

## Browser and web integration (agent ses_dfbd8cdaaffe9U2GzMjvsHeh1a)

Consistent: skel mimeapps.list:56-83 maps all web types to Vivaldi; SettingsDefaultApps.qml:22,79 changes browser. Edges broken:

1. **Web Apps never open in app mode.** WebApps.qml:92 generates Exec looking for host binaries (chromium/vivaldi/…) but image has none (Vivaldi is Flatpak; exported Exec is `/usr/bin/flatpak run … --command=vivaldi …`). Every entry falls to xdg-open, losing --app=/--class/--name. Sketch: emit `flatpak run --command=vivaldi com.vivaldi.Vivaldi --app=<url> --class=…`.
2. **Changing default browser is partial.** SettingsDefaultApps.qml:22 sets only https/http/text/html, while skel pins xhtml, ftp, about, chrome, unknown, 5 x-extension-*, 3 mhtml, 2 manifest types. Sketch: extend browser.types to every web type.
3. **XF86WWW uses different resolver.** etc/niri/config.kdl:253 uses `xdg-settings get default-web-browser` while Settings uses gio mime; shell's own comment calls xdg-utils 1.2.1 unreliable. Sketch: query gio mime and pass desktop id to launch-app.py.
4. **No icon fetch for web apps.** WebApps.qml:13,42 creates webapps/icons but never writes it; SettingsWebApps.qml:82-86 offers only free-text icon name; curl/apple-touch-icon is comments only (WebApps.qml:106-109).
5. **"Open containing folder" has no implementor.** Vivaldi granted org.freedesktop.FileManager1=talk, DesktopIcons.qml:129-130 calls ShowItems, but niri ships no Nautilus and files.py registers no D-Bus name. Sketch: implement FileManager1.ShowItems in files.py.
6. **Web apps cannot be URL handlers or share targets.** WebApps.qml:89-101 has no MimeType/Actions; no manifest read, so share_target never becomes OS target.
7. **No password/autofill bridge.** Vivaldi has Secret Service access but its own encrypted store; shell Passwords is metadata-only passkey registry; "Browser reference" just a source label (PasswordsWindow.qml:424).
8. **No tab handoff / send-to-phone.** shani-link can open a link on phone over adb (shani-link/README.md:25-29) but no extension/share-sheet/command.
9. **No web-based settings / web-app → shell IPC.** No HTTP settings surface; Quickshell IPC not reachable from web content.
10. **No download layer.** No XDG_DOWNLOAD_DIR in skel, no manager, notification, scan hook or bandwidth control.
11. **No isolated profile, notifications or per-app shortcuts.** --app= alone shares Vivaldi's profile; no --user-data-dir.
12. **No x-www-browser provider.** Grep empty; CLI tools calling it have nothing to launch.
13. **No image-level browser privacy policy.** No Vivaldi policy JSON; tracker blocking/DoH/fingerprinting are defaults only.
14. Vivaldi's password store independent of Passwords/keyring semantics.
15. Web Share API target support depends on Vivaldi PWA implementation, unconfigured.
16. Browser version/updates Flatpak-only with no shell page.

## App permissions and sandboxing (agent ses_dfbd89f9bffetyoog40cma42kr)

**Important correction:** Flatseal-style per-app permission editing IS built (`SettingsAppPermissions.qml` switches for share/sockets/devices/features/filesystems, folder add, portal answers, D-Bus talk names, env, Reset; `bridge/flatperm.py`; `dev/shell-parts/app-permissions.sh`; `tests/test_flatperm.py`). Do not re-file that headline gap. Residual:

1. **Microphone grant cannot be edited.** flatperm.py:35-37 PORTALS omits microphone though SettingsPrivacy.qml:22 knows devices/microphone. [FIXED in this pass]
2. **Software's app page read-only, never links to editor.** SoftwareWindow.qml:109-110,424-442 prints flatpak info as text; editor at SettingsPage.qml:1531. Add "Change permissions…" button.
3. **--user overrides vs --system installs.** Image apps installed with `flatpak install --system --or-update`; flatperm.py:100,115,143 only uses override --user; only test is stand-in. Needs real-system verification.
4. **Parental blocking UI-only, not enforced at launch.** AppFilter.allowed() only in Launcher.qml:262, Dock.qml:113,189, TvHome.qml:42,59; bridge/launch-app.py has no check, so terminal/gio launch/autostart run blocked apps. [FIXED in this pass via SHANI_APPFILTER_TOOL gate]
5. **Persistent (AppData) folders parsed but invisible.** flatperm.py:32-33 returns persistent in show(); SettingsAppPermissions.qml:82-113 only renders filesystems.
6. **D-Bus name ownership no UI.** flatperm.py:39-40 accepts own-name/system-own-name/no-own-name, but SettingsAppPermissions.qml:268-269 exposes only talk-name.
7. **devel toggle with no warning.** SettingsAppPermissions.qml:100 offers "Development — debuggers, ptrace" with no caution that --allow=devel voids the sandbox.
8. **No developer-mode gate for sideloading.** AppImage add, .flatpakref install, generated apps available to any user.
9. **No restart affordance after permission change.** SettingsAppPermissions.qml:7 admits "next time it starts" but no restart.
10. **malcontent fields beyond app IDs never read.** appfilter.py:51-52 reads only is_appinfo_allowed(); OARS/content ratings and install flags ignored.
11. **No confinement for shell-launched apps or bridges.** launch-app.py:118-131 uses systemd-run --user --scope (cgroup lifetime only). AppArmor enabled but profiles only for snapd.
12. **One shell app can read another's data.** Notes plaintext, Contacts vCards, Calendar EDS, Passwords Secret Service; all bridges run as user with full home access.
13. **AppImages run with full privilege.** appstore.py:555 chmod +x, :599-602 writes desktop executing binary directly.
14. **Studio-generated apps unconfined.** Studio.qml:18,49; StudioWindow.qml:3 drops desktop file with no review/sandbox.
15. **First-use prompts entirely external.** niri-portals.conf:7 delegates Access to gtk; shell never shows camera/mic/location prompt.
16. **USB permission is one coarse switch.** SettingsAppPermissions.qml:95-98 only devices/all.
17. **Firewall not per-application.** Firewall.qml:122-153 services/ports/rich rules/zones only; no app-identity match.

## Onboarding, tutorials and in-app help (agent ses_dfbd86d5bffeVBccYb0KKykJQ5)

Surveyed 45 AppWindows, Common tooltip/empty-state helpers, Tour, Hints, SettingsShortcuts, SettingsAbout, launcher actions, setup, shani-docs.

1. **No per-app Help/"?" button in any app.** Common/AppWindow.qml:33,120-153 exposes only tools + window controls; sole help button is shell chrome SidebarHeader.qml:186; no F1 handler (KeyFocus.qml:6,114 handles Menu/Shift+F10).
2. **No link from shell to documentation.** shani-docs/CNAME = docs.shani.dev; no QML references any docs URL; SettingsAbout.qml:174-187 offers Copy details/Problem report/Cassini only.
3. **"Explain why" help exists but used once.** SwitchRow.qml:13,39-51 has info property with help icon; only SettingsPage.qml:1288 sets it across 28 files.
4. **That "why" help is hover-only and invisible to AT-SPI/keyboard.** SwitchRow.qml:42-51 ToolTip on MouseArea.containsMouse; Icon has no Accessible role/focus. Hint.qml:18-26,30-61 HoverHandler only, PopupWindow label no accessible name.
5. **Shortcut list can't be printed/exported/grouped by scope.** SettingsShortcuts.qml:37-49 lists niri binds with filter, custom binds at :52; no copy/print/export.
6. **Existing shortcuts cannot be rebound.** SettingsShortcuts.qml:67-170 only adds custom binds; takenBy() refuses keys already bound.
7. **Ui.shortcutsListed is test-only counter, never shown.** Common/Ui.qml:152, set at SettingsShortcuts.qml:25, read only in shell.qml:1146 state dump.
8. **"?" in launcher means "ask Chronoa", not help.** Launcher.qml:528-535 strips leading ?. Discoverable cheat sheet is niri's static overlay.
9. **No progressive onboarding checklist.** Only tourSeen/launcherOpens/startHintsDone (Settings.qml:516-519); Tour.qml:39-43, StartHints.qml:16 retires at 5 opens.
10. **Empty states often give no next step.** EmptyState.qml:12,48-54 has action button but only 7 instances set actionText; FilesPanel.qml:1043-1048 and FilePickerPanel.qml:248-252 no action.
11. **No app-level "What is this?"/"How do I?" help mode.** WindowMenu.qml:68 sends only title; no F1 handler.
12. **Tooltips mostly say WHAT not WHY.** TextEditorPanel.qml:26-28 encodes keys in text; only 3 of 23 Hint uses pass keys.
13. **Setup wizard has no help/learn-more path.** setup/shell.qml has one tip (:1191) and no help affordance.
14. **Capture tools have no in-place help.** PinCapture.qml no tips/help.
15. **"All keyboard shortcuts" bypasses our searchable list.** Tour.qml:132 and LauncherActions.qml:69 call niri show-hotkey-overlay.
16. **Launcher help actions global, never contextual.** LauncherActions.qml:55,69,70,76 = Tour, shortcuts, About, none targeting focused window.

## Other desktops and OS migration (agent ses_dfbd83d3cffe7UbRYbEImt7E41)

Part A — features from desktops not yet compared:

| Idea (desktop) | What they do | ShaniOS today | Feas. | Sketch |
|---|---|---|---|---|
| HUD — type a menu command (Unity) | Alt + fuzzy-type any app menu action | app menus in bar via bridge/appmenu.py; Launcher is ranked command list | High | HUD overlay filtering appmenu + shell actions via Launcher ranker |
| Named panel profiles (XFCE) | Save "Work"/"Me" panel layouts | 2 automatic dock states + 6 presets (Docking.qml:20-22,33-55), none user-named | High | Generalize Docking.snapshot() into named profiles |
| Desktop right-click menu (Pantheon) | New Folder/Paste/New Document on desktop | DesktopIcons.qml:31,84 but only wallpaper menu | High | Context Menu on DesktopIcons delegating to files.py |
| A–Z scrubber in app grid (Pantheon) | Alphabetical side index | Category chips only (Launcher.qml:264,745-748) | High | Side ListView index jumping grid by first letter |
| Scopes in launcher (Ubuntu Touch) | Live cards (weather, agenda, feeds, music) | Ranked apps/actions/files/windows; services exist | Med | "Today" section of 3–4 service-driven delegates |
| "Make it look like Windows/macOS" presets (Zorin) | One-click habit layouts | 6 presets target form factor/perf | High | Preset moving bar to bottom, window controls left, Start-style grid |
| Interactive shortcut cheat sheet (COSMIC) | Overlay lists/filters every keybinding | Tour + session.kdl, no live binding list | Med | QML sheet parsing session.kdl binds with search |
| Auto workspace-per-app (Pop!_OS) | Each app's new windows land on own workspace | Manual moves + drag-to-map | Med | Per-app workspace map in Settings > Windows |
| Multiple independent panels (MATE/LXQt) | Top + bottom panels, own applets | One bar + one dock | Med | Second layer-shell panel instance |
| 10-foot mode (SteamOS) | Controller/TV detected → bigger scale | Gamepad stack + TvHome but manual | Med (hardware) | Preset bound to TvHome + dockIconSize/bar scale |
| Ambient cover card (Sailfish) | Always-on active-app card | Lock screen notifications/media | Out of scope (hardware) | Software-only: lock-screen active-task card |
| Task handoff to nearby device (HarmonyOS) | Continue task on phone/tablet | shani-link pairs phones, no handoff | Out of scope (server) | Local "Open on paired phone" via shani-link send |

Part B — OS migration:

| Gap | Evidence | Feas. | Sketch |
|---|---|---|---|
| Browser bookmark import from Chrome/Firefox/Safari HTML | No parser in bridge/; switching-from-windows.md:30 | High | Netscape bookmark HTML bridge |
| Password import (Chrome CSV, KeePass, Bitwarden) | passwords.py:16-17 only GPG import/export | High | Importer with delete-plaintext prompt |
| Mail import (PST, Apple Mail, mbox/maildir) | mail.py IMAP+SMTP only; docs delegate PST to Thunderbird | Med | mbox/maildir bridge; PST via libpst |
| CalDAV/CardDAV account import | Only .ics/.vcf file import; Online Accounts declined | Med | Account-based sync bridge |
| Guided "copy my Windows drive" with ownership fixups | files.py:1278-1300 mounts; drives.py:19-27 formats NTFS | High | Copy user folders then chown via take-ownership |
| BitLocker drive status + recovery-key UI | files.py:1278-1282 generic gio prompt | Med-high | Detect via udisks HintEncryptionType + unlock dialog |
| APFS read / Time Machine import | Guide says restic/borg cannot open Time Machine | Out of scope | Honest "export on Mac first" checklist |
| iPhone/iMessage/WhatsApp backup restore | Guide covers iCloud photos only | Out of scope | Guided export checklist |
| Android restore (photos/contacts/APKs into Waydroid) | shani-link pulls contacts via PBAP/KDE Connect | Med | ADB pull bridge + APK install |
| macOS shortcut muscle-memory mode (Cmd→Super) | SettingsInput.qml:121-124 only keymaps | High | Preset applying niri binds + GTK/Qt Mac key themes |
| In-shell "what replaces Photoshop/Excel/Outlook?" | Guide tables exist; Software has ODRS but no need→app mapping | High | Launcher "I want to…" action using APPS catalog |
| First-run migration step in Setup | first-account.py only creates account | High | Setup page linking importers + switcher guide |

Top value × ease: password/bookmark import, first-run migration step, in-shell app-equivalent helper, macOS shortcut mode, guided Windows-drive import, named panel profiles, Unity HUD.

---

# Sixth pass — full reports

## AI / Chronoa integration depth (agent ses_dfbee5a26ffen4INA5q71nFPvp)

Feasible in the shell (ranked):

1. **No conversation history / new / switch / delete.** Panel transcript is one in-memory ListModel, wiped with shell; backend already has reset-conversation/switch-conversation/delete-conversation actions. (ChronoaSurface.qml:10-11; backend app/application.py:1849-1861) Add header "New / History" menu driving those D-Bus actions.
2. **Scripted `approve "deny"` can grant "Allow this once".** optionFor() forwards options[0] (allow) for any unrecognised decision — exactly what its own comment warns about. (ChronoaPanel.qml:201-214, shell.qml:327-332, FINDINGS.md:175-179) Match deny/always semantically or reject unknown labels. [SECURITY BUG — fixed in this pass]
3. **Cloud fallback invisible in the Island.** Backend emits notice "A cloud provider answered this turn"; shell puts it in transcript only, never bar pill. (agent_service.py:213-214; ChronoaSurface.qml:47-48; Island.qml:80-93) Set lastCloud flag on that notice and show cloud chip.
4. **Tool-choice ("selection") events silently dropped.** Agent emits record of which tool chosen and why; neither handler has a case. (agent_service.py:26,206-207; Chronoa.qml:72-105) Render expandable "chose <tool> because …" line.
5. **Suggested prompts static.** Four hard-coded chips (Battery/Summarise screen/Tidy desktop/Dictate), no adaptation to focused app/clipboard/notification. (ChronoaPanel.qml:751-757) Derive from Niri.focusedWindowId, Smart.suggestion, SmartReplies.
6. **Window context is a title string.** "Ask Chronoa about this window" sends only title + app_id; file handoff sends paths as prose. (WindowMenu.qml:67-68; FileActions.qml:156; Island.qml:359-379) Attach window id, workspace, app, selection, accessible summary.
7. **No per-turn local/cloud or model switch in panel.** Model chip read-only; defaultProvider informational. (ChronoaPanel.qml:359-375; AIProviders.qml:88-92) Make chip a menu of installed models/providers.
8. **Assistant replies plain unformatted text** — no Markdown, links, code blocks, copy/regenerate/feedback. (ChronoaPanel.qml:547-577) Render with backend markdown_lite.py and add copy/regenerate.
9. **Panel state labels untranslated** ("listening", "thinking", "speaking", "waiting for you", "offline", "ready") while rest uses Tr.t. (ChronoaPanel.qml:79-91) Wrap in Tr.t().
10. **No voice/wake/barge-in controls in Settings > Chronoa.** Backend actions toggle-wake-word/toggle-barge-in-vad/toggle-cloud-fallback exist; shell surfaces only enable/kill. (SettingsChronoa.qml:24-43) Add three switches.
11. **No push-to-talk in shell conversation.** Mic is tap-to-toggle. (ChronoaPanel.qml:843-877; Dictation.qml:26-31) Bind hold key to toggle-listening/stop-speaking.
12. **Approvals have no audit trail or per-app "always" granularity.** (ChronoaPanel.qml:191-195,715-724) Keep shell-side decision ledger keyed by turn + app.
13. **No privacy/memory controls on shell side.** All sense consent and forget live in Chronoa's own window. (SettingsChronoa.qml:24-43) Expose key sense toggles + Forget button.
14. **No streaming cancellation affordance.** submit() refuses input while busy; stop button only stops speech. (ChronoaPanel.qml:229-236,859-877) Add Cancel button in working state.

Needs backend/model:

15. **Cannot cancel a running turn.** Agent has only Turn/Approve/Write/FindFiles; bridge has no cancel op. (agent_contract.py; chronoa-bridge.py:191-222) Add Cancel(turn_id) + Event.
16. **No persistent screen sharing / live context.** Shell passes one-off screenshot/Lens-region paths in prose; backend vision per-turn. (Lens.qml:69-77; Screenshots.qml:140) "Share screen with Chronoa" toggle streaming frames.
17. **No camera input to Chronoa.** Camera captures stills but no "ask about viewfinder." Add camera-attach button.
18. **No shell-app tool/prompt registration.** Backend MCP server exposes skills to Claude/Cursor but Shani apps/Hooks cannot register tools. (backend mcp.py) Define desktop-entry X-Shani-Chronoa-Tool manifest + MCP bridge action.
19. **No per-app data-access provenance.** Consent sense-based in backend; events carry no "which app asked." Add caller/app id to events.
20. **Model management disconnected from live model.** Models reads ollama list only; panel guesses label from setting. (Models.qml:44-75; ChronoaPanel.qml:30-39) Expose live model/provider registry D-Bus property.
21. **Voice output has no in-shell voice/style controls.** TTS/voices exist in backend. (Island.qml:111-118) Add voice/style pickers and in-panel playback bar.
22. **No multi-session or cross-device continuity.** One turn at a time (TurnFilter holds 8 unclaimed turns). (turn_filter.py:38-40) Needs session id in Agent contract + resume/handoff action.

## Automations, hooks and routines (agent ses_dfbee2c1affe92UHA7pi636FT8)

Shell rule engine (Services/Automations.qml):

1. **Captured special keys silently discarded when bind written.** SettingsShortcuts.qml:71-80 can capture F1-F12/Space/Return/arrows/Home/End, but InputConfig.qml:146 keeps only /^[A-Za-z0-9+_]+$/. Fix filter to emit niri key names.
2. **No way to fire a rule manually.** act() private; no IPC method/palette entry/keybind. Expose fire(index) over shani ipc and add to action presets.
3. **Trigger vocabulary is 5 items.** holds() :32-42 supports only wifi/power/output/displays/time; Chronoa engine has 19 event types. Add app focus/window title, notification, clipboard change, USB/BT device, battery level, file change.
4. **Action vocabulary is 6 items.** act() :43-55 = focus/dnd/volume/style/open/run. Missing notify, play sound, lock/sleep, arbitrary setting, open URL, media control.
5. **Failures invisible.** Automations.qml:51 execDetached discards exit status and stderr; Hooks.qml:25-29 only catches synchronous spawn failure. Capture output, log history, toast failed run.
6. **No loop or rate guard.** :56-65 edge-triggered only; a run that reverses its own trigger can ping-pong forever. Add cooldown and max-fires-per-minute.
7. **Five unrelated "when X then Y" systems.** Shell rules, shell hooks, keybinds, Chronoa event rules, Chronoa phrase routines — separate stores/formats/UIs/logs. Unify.
8. **notificationRules is a dead setting.** Common/Settings.qml:260 declares it; Hooks.qml never reads it. Implement or delete.
9. **No templates, import/export, sharing.** SettingsAutomations.qml:100-283 builds from scratch. Add starter templates, export/import, shareable file/QR.
10. **No dry-run/test.** No "what would this rule do right now?" Add Test button calling holds(r) without act().
11. **Rule edits have no undo.** SettingsAutomations.qml:37,60,62 writes immediately. Add rule-level undo.
12. **GUI caps at 3 screens and 6 volumes.** SettingsAutomations.qml:184 offers only "1","2","3" though holds() parses any integer; :236 offers 0/20/…/100. Generate from Displays.outputs.length; use slider.
13. **Hooks share one global on/off.** Hooks.qml:21 gates all six. Add per-hook enable and failure indicator.
14. **User scripts unpermissioned.** Hooks.qml:27 and Automations.qml:51 run sh -c as full desktop user with no confirmation, timeout, audit. Add opt-in confirmation and bounded timeout.
15. **Time rules daily-only.** No weekday mask, one-shot, sunrise/sunset, timezone. Appearance.qml:28-73 already computes sunrise/sunset; reuse.
16. **Startup quirk for time rules.** prime() :71 excludes `r.when !== "time"`, so a rule matching current minute at startup waits for next boundary. Offer "fire now if due."
17. **Wi-Fi match exact string equality.** :35; output uses case-insensitive substring :37. Add regex/SSID-picker semantics.
18. **No named/sound notification action.** Notify exists as shell service but no then:notify and no sound action. Add both.

Routines (Chronoa) and trigger engine:

19. **Routines phrase-only, not scene/schedule-driven.** routines.py:54-73 matches whole utterance; skills/routines.py:13 only save/list/delete. Add schedule/app/location triggers and ordered steps.
20. **No import/export/sharing of routines.** routines.save_all() writes one local JSON.
21. **Percept rules have no unattended product caller.** TriggerEngine reachable only via CLI. Wire into daemon.
22. **Event-rule authoring skill-driven, not first-class GUI.** skills/manage_triggers is only writer; shell Settings never sees 19 types.

Absent across all five systems: variables/expressions, if/else, wait/delay steps, subroutines, loop/iteration, run history with replay, dry-run, rule versioning.

## Window management / niri depth (agent ses_dfbee0299ffe3pKGx7kD91MV6L)

1. **Column swap absent from UI** (only per-window swap exists). WindowMenu.qml:49-50 offers swap-window-left/right; niri's swap-column-left/right never called.
2. **Fullscreen/float/maximize menu labels never reflect current state.** WindowMenu.qml:38,40,41,45,46 issue actions but fixed labels; windows carry is_floating only.
3. **Force-kill works only on focused window.** Niri.qml:458-464 kills focusedWindow.pid; shell.qml:931 windowClose only polite close-window. Add forceClose(match).
4. **No create/delete workspace action.** Rename exists, reorder via move-workspace-up/down, but no new/close.
5. **Overview search throws away context.** OverviewSearch.qml:31-35 closes overview and hands string to launcher.
6. **Urgency displayed but never acted on.** Niri.qml:404-411 tracks is_urgent; bar/map colour it but no focus-urgent.
7. **Edge swipes four hard-coded actions only.** EdgeSwipe.qml:14-33; no per-edge assignment; no per-edge disable.
8. **No workspace-level drag reorder.** Drag proxy exists in Bar.qml:237-247 for windows but workspace chips have no drag target/source.
9. **"Move workspace to monitor" only goes to next monitor.** WindowMenu.qml:60-61 uses *-next; named targets exist only in IPC.
10. **Resize percentage-only; no exact pixel or per-height UI.** WindowMenu.qml:52-54 set-column-width percentages.
11. **Floating-workspace key not monitor-namespaced.** WorkspaceLayout.qml:15 keys by ws.name || "output:idx"; named workspace on two monitors collides.
12. **Session restore brings back app identities, not layout.** Reopen.qml:20-38,89-94 stores only desktop entry ids; geometry/column widths/workspace/monitor lost.
13. **No focus-stealing/new-window focus policy.** Urgency events arrive but no focus-new-windows or allow-list setting.
14. **Swap monitors only swaps two active workspaces.** Niri.qml:210-234; no UI to pick which workspaces.
15. **No focus-previous-workspace bind or UI** (previously noted, still open). session.kdl:260-274 has no focus-workspace-previous.
16. **Overview has no window-level actions.** OverviewStats.qml:37-42 can only close all.
17. **Trackpad gestures entirely compositor-owned.** session.kdl:19-25 says three/four-finger gestures built-in with no config. OUT OF SCOPE.
18. **No monitor-hotplug workspace placement restore.** Docking.qml:20-29 restores bar/dock/gaps but not output→workspace map.
19. **No niri crash-recovery UX.** Niri.qml:466-472 reconnects after 1.5s but no banner/config check.
20. **Always-on-top genuinely impossible.** Niri.qml:152-180 floated-window carry instead. OUT OF SCOPE.
21. **No Activities/multi-workspace-set abstraction.** OUT OF SCOPE.
22. **No window thumbnails in switcher/overview.** Switcher.qml:1-8 notes niri has no per-window capture protocol. OUT OF SCOPE.
Already correct: focus-follows-mouse, warp-pointer, workspace double-tap-back, named workspaces, per-app open-on-workspace rules, hidden workspace names, resize/snap presets.

## User documentation accuracy (agent ses_dfbedda7affeky9ejG2QXE0VRT)

HIGH:
1. Generated HTML stubs for overview/faq/troubleshooting stale (2026-11-01 vs markdown 2026-11-22). Omitted whole app section, new Q&As, new troubleshooting entries; showed "Updated 2026-08-28" and old provider list "OpenAI, Anthropic, Mistral". [FIXED in this pass: regenerated]
2. Edition count contradicted in five intro/FAQ files — COSMIC still "announced"/"upcoming" though it builds today. [FIXED]
MEDIUM:
3. Troubleshooting omits new bridge/dependency failure modes (smartctl, picocom, GeoClue, llama-server, at-spi2-core, rclone); shani-doctor.py checks none of them. [FIXED: dependency table + doctor checks]
4. ~70 mass-pass features have no user-facing home in shani-docs. [FIXED: Recent refinements section in overview.md]
LOW:
5. Wrong app name: docs/faq.md:117 "Translator" should be "Translate". [FIXED]
Checks that passed: app count 50 consistent; 7 PDF tools verified; provider list verified; i18n 3684 matches; stable version consistent; 0 broken internal links; no bad flags/subcommands.

## Security and privacy depth (agent ses_dfbedadb7ffeSpA71WgJoYFafm)

1. **[CRITICAL]** MOK private key shipped inside base image (shani-install-media/SECURITY.md:30-34) and two real keys retrievable from git history (AUDIT-HISTORY.md:63-71) — rotate + rewrite history. Podman builds SigLevel=Never, AMI soft-fails verification.
2. **[high]** 45 s clipboard clear covers 1 of ~25 copy paths (only PasswordsWindow.qml:126 arms wl-copy --clear). OTPs (6-digit) admitted to cliphist. Phone share leaks clipboard with no confirm.
3. **[high]** Suspend can happen unlocked (Lock.qml:33-38 when lockBeforeSuspend false); notification previews toggle also governs agenda/media titles (LockScreen.qml:254,399,532); no audit trail of unlocks/grants/admin/deletes.
4. **[high]** polkit caller() silently passes when PKEXEC_UID unset (shani-admin.py:138-143); settings.json 0644 holds clipPins/server URLs; clipboard encryption off by default; Flatpakref installs from arbitrary URLs without showing remote; AppImage chmod +x without signature check; no per-request consent for cloud LLM.
5. **[med]** Camera kill switch unloads only uvcvideo; no DoH/DoT; no WebRTC leak protection; no TPM/Secure Boot state in shell; voice recordings/transcripts/call logs no retention control.
Deliberate win: no log upload, "Nothing is sent" in About.

## Installer / upgrade / recovery UX (agent ses_dfbed7fe4ffeh5E3GaZpLAUAWg)

Shell-fixable: failed update toast no cause/retry; pending reboot cannot defer; no update history on Updates page; no support bundle at failure; no last-checked time; health results text-only; setup failure raw error with no retry; no Wi-Fi-only/metered warning; channel switch no explanation; Boot & Recovery read-only; two divergent health systems; Settings About no in-OS recovery entry.
Installer/daemon: no basic-graphics/safe-mode boot entry; image size/ETA not in deploy JSON; health recommendations not in JSON; no reinstall-keeping-files; snapshot restore manual btrfs; failed-install help button dead (no browser on live ISO); encryption choice/recovery key not explained at install; metered enforcement needs daemon.
Deliberate win: no log-upload consent flow.
Two-desktop comparison: Shani beats on blue-green rollback and phase-level progress, weakest on pause/history/safe-mode/keep-files and failure-to-action bridge.

## Specialized subsystems (agent ses_dfbed4f92ffeR6nblD85IEc7PS)

Printing (driverless setup/default/test page already exist): missing ink/supply levels, scan-to destinations, real print dialog (copies/page-range/duplex/preview), in-shell job queue with cancel/hold, printer-state alerts.
Fonts system: missing hinting/antialiasing UI (hardcoded in Appearance.qml:130), font DPI control, font uninstall, cache refresh watcher.
Gamescope console (full session ships in separate package): missing MangoHUD overlay control, per-game TDP/frame-cap profiles, in-game screenshot/recording hotkeys, controller-remap/fan-curve tiles.
Casting: missing cast session state/sink list/stop, mirror-area choice (--fullscreen hardcoded), audio routing with cast.
Time/date (settings UI otherwise solid): missing NTP server config, sync status/source readout, dual-boot RTC mode, timezone-change feedback.
Freedesktop compliance: cross-volume trash restore, recent-files destruction by Housekeeping.qml:27 (truncates all apps' recents daily), thumbnail metadata/cache bound, more thumbnail sizes.

All sixth-pass verdicts static; no runtime/hardware/PAM/TPM/printer/gamescope/live-deploy verification.

---

# Fifth pass — full reports

## Reliability and data integrity

1. **Deterministic temp filenames defeat atomicity under concurrency:** feeds.json.tmp (feeds.py:72), conf.json.tmp (mail.py:67), appstore-index.json.part (appstore.py:216), starred.tmp (files.py:799), library.json.tmp (music-library.py:164,221), translate.py:185, copyjob.py:91, u2f.py:65. A refresh timer and user action racing can interleave writes and corrupt JSON, then silently reset. Use tempfile.mkstemp(dir=path.parent).
2. **files.py:1684 writes bookmarks with direct open("w")**, truncating before new content — crash/ENOSPC leaves empty file. AppImage desktop entries same (appstore.py:599).
3. **Singleton races:** TerminalApp.qml uses one shared cbStore/testProc for Test Connection — two quick clicks strand one callback. QuickNotes.qml uses one crypto Process with four shared mutable fields (mode/pendingPass/newName/payload) — autosave racing lock applies wrong mode.
4. **Keyring.qml:26-33 hides write failures with || true** — same class as "AI keys never stored". Locked keyring or full disk silently loses secret.
5. **bridge/lock.py no timeout on three of four gpg calls** (:139,146,235) and 3600s on fourth; blocked pinentry hangs Files bridge. convert.py conversions no timeout/SIGTERM cleanup; QML Process no watchdog (bsdtar, pdftoppm, wf-recorder, libcamera can leave UI stuck).
6. **nearby.py receive leaves .part files** with no startup sweep/resume after crash; clipboard-crypto.py can leave plaintext .db.wrap symlink after SIGKILL; conversions/transfers accumulate .part across crashes.
7. **Voice Recorder takes lost on ungraceful SIGTERM/logout** — only SIGINT finalizes Opus (VoiceRecorder.qml:90-105).
8. **Disk-full errors hidden:** feeds.py/mail.py never check write result and UI reports success. Caches keyed only by path+mtime (appstore.py:206, music-library.py:145, files.py:960). Tasks.qml:75-86 assigns JSON.parse output with no type check — {} breaks every delegate. files.py:1672 re-records IPC paths without rejecting newlines or "..".

## Offline and network resilience

1. **[shell-fixable]** Proxy settings never reach running bridges — Proxy.qml writes gsettings + environment.d for next login while bridges inherit startup env; SOCKS mode sets no ALL_PROXY.
2. **[high]** mail.py IMAP calls no timeout (:376-382); Updates.qml:66-69 no timeout/re-entrancy guard — one hung shani-deploy wedges all checks; fwupdmgr likewise. Translate interactive requests inherit 300s batch timeout.
3. **[high]** Captive-portal detection exists (Net.qml:22-40) but apps emit generic errors; Weather keeps stale values with no "as of"; Feeds stores fetched but never shows; Radio wipes list on any error; Mail no offline/empty distinction.
4. **[med]** No 429/503 handling on geocoding/OSRM (curl -sf collapses generic); Feeds retry no backoff; multi-GB model/Flatpak installs on metered connections; Flathub streams no timeout.
5. **[daemon-level]** Landline SIP TLS disables verification and read timeouts (shani-link/.../ua.py:186-193); deploy retries fixed delays and honour no proxy.
Already good: Chronoa cloud LLM exponential backoff with jitter; most API probes bounded; Screenshot OCR fully local.

## Search and navigation depth

1. **[high]** Feeds and Mail invisible to launcher global search (Launcher.qml:370-489); contact search only name/phone/email; event search title-only; content search hardcodes folders instead of Settings.data.searchFolders.
2. **[high]** `>` is raw sh -c runner, not a command palette — no fuzzy command list, descriptions, recent commands, argument completion.
3. **[high]** Matches never highlighted in launcher results despite Common/HighlightText.qml; no saved/recent searches.
4. **[med]** Launcher category chips disappear once query typed (keyboard users lose filtering); Escape closes rather than unwinds; no shared document MRU; no focus-last-workspace keybinding; no named-workspace-by-name navigation; scratchpads no cycle/list.
5. **[med]** Chronoa handoff from launcher result passes only query or file path — selected contact/event/note identity discarded.

## Theming and visual customization depth

Correction: automatic dark schedules (time-of-day AND sunrise/sunset) already exist (Appearance.qml:28-73) — not a gap.
1. **[high]** Font hinting/antialiasing hardcoded (Appearance.qml:130); no independent lock-screen wallpaper; accent one global token with fixed alphas; bar height/opacity constants.
2. **[med]** No online wallpaper sources/transition choice; slideshow/live wallpaper global while still wallpapers per-monitor; bar widgets toggle but not reorder (control-centre tiles do); icon/cursor themes no preview and require restart; no theme export/import; focus ring fixed #ff7f50 in session.kdl rather than Theme.accent; no window-border toggle; matugen templates hardcoded to one GTK template; no wallpaper-specific day/night schedule; font sizes fixed 10-14; no compact/dense bar mode.
Out of scope: server-side titlebars, per-window transparency, colour filters/gamma/HDR, pointer effects.

## Performance and scalability

Measured: 348 QML files, 143 services, 75 bridges, 191 Timers (54 repeating), 86 running:true bindings (72 eager Processes), 64 ListViews (16 without reuseItems/cacheBuffer), 473 Repeaters, 272 execDetached calls.
1. **[high]** Viewer thumbnail strip decodes every image full resolution no sourceSize/asynchronous (Viewer.qml:494-510); main image synchronous uncapped (:92-104); wallpaper preview likewise.
2. **[high]** Launcher whole app grid via Repeater rather than recycling GridView; 18 ListViews no reuseItems/cacheBuffer; live notifications unbounded; Feeds read-state map and Photos metadata never prune deleted items.
3. **[med]** 72 eager Processes at startup (~40 one-shot command -v probes); Photos re-walks Pictures every open; Music library re-walks every open; 10s /proc/*/fd polling fallback in Privacy.qml:42; one wtype process per OSK keystroke; two always-on 10-minute timers in Tasks/Agenda.
4. **[med]** dev/shell-test.sh has real budgets but no large-data fixture and 30s idle window cannot catch 10-minute timers.
Already good: Common/Proc.qml debounces/times out; Files.qml persistent worker with watchdog; process/stats polling gated on visibility; app windows LazyLoaded.

## Input methods and multilingual text entry

Handwriting genuinely implemented (WritePad.qml, bridge/handwriting.py).
1. **[high]** Plain TextFields no undo/redo; OSK no emoji page, no paste key, no key repeat; no IME preedit/candidate integration; Indic handwriting silently degrades to English OCR and only tesseract-data-eng ships.
2. **[med]** No long-press accent popups; pre-desktop keyboard Latin-only; voice typing tap-to-toggle no push-to-talk; no spellcheck, password autofill, autocapitalize hints, deterministic text expansion or per-app IME profiles; no one-handed OSK mode; no swipe typing.
3. **[low]** Mixed-script font fallback relies on fontconfig but no render test; switch access absent (eye/head pointer compositor-level).

## Notification and alerting depth

1. **[high]** resident hint ignored so persistent popups auto-expire; low-battery (15%) and peripheral alerts normal urgency suppressed by DND while only 7% critical; no call/message or repeat-caller DND exceptions; snooze relative-only, loses actions/urgency, no list UI, re-delivers up to 20s late after boot.
2. **[high]** No per-app sounds/volume/vibrate, no escalation, no unified silent gate across sound/flash/speech, no storm coalescing. Lock-screen notifications inert Text rather than actionable NotificationCards.
3. **[med]** Any app can self-declare urgency 2 bypassing DND/rules/silent-apps; DND dndUntil bypassed by automations; history capped at 50 with no export/TTL; Backup/PdfSigner/VoiceRecorder/Camera completion notices no "open result".

## Test and docs consistency after mass pass

1. **[critical]** shani-shell PKGBUILD was 9 commits behind, would install package with none of new features — repinned to 4772748, pkgrel=40. [FIXED]
2. **[fixed]** 77 stale [open] markers flipped to [built — mass pass]; integration/deps note corrected; check counts 700+→800+.
3. **[open]** 11 of 21 test_gap_*.py files pure source-string assertions that cannot catch runtime breakage; hi.json/mr.json remain 1525 keys while template.json grew to 3684 — 242 new strings ship English-only.
4. **[fixed]** data/whats-new.md and FEATURES/README app catalogue updated with mass-pass capabilities.
5. **[open]** No test asserts PKGBUILD pin tracks HEAD; no translation-catalog parity test. Podcast enclosures are metadata + link, not download queue.

---

# Fourth pass — full reports

## Cross-app integration and data portability

Tier 1:
1. **mailto: has no handler** — dev.shani.Mail.desktop empty MIME list (bin/shani:524-525), niri skel no default, XF86Mail falls to browser. Register x-scheme-handler/mailto + message/rfc822.
2. **Share sheet no targets into our own apps** — Services/Share.qml:20-35 only KDE Connect/Bluetooth/LocalSend/QR/xdg-email/clipboard/gio; Photos no share action. Add Notes/Photos/Editor targets.
3. **Copy-path copies plain text, not text/uri-list** (Viewer.qml:287, TerminalAppWindow.qml:328), cannot paste as file. Mail compose/Text Editor/Photos no inbound DropArea.
4. **Apps never write recently-used.xbel** — Launcher recents one-way from GTK. Calendar ICS import but no export. Notes .md and Contacts .vcf no default associations.
5. **geo:/web+*/obsidian:///file:// no registration or dispatch policy.** Desktop entries emit no Actions=.
6. **No portable data bundle** ("take my data to another OS") — Photos/Mail/Passwords no export UI.
7. **Mail cannot attach a file** — send() takes no file list; Share's Email target shells xdg-email bypassing Mail.
8. **Portal backend implements only FileChooser** — Email/Share/SendFlatpak intents bypass shell. Rich-text/file-URI clipboard formats dropped.
9. **No notification→file affordance;** portal/share handoffs call Ui.closeAll() discarding surface; Files bookmarks no import/export; no shared cross-app session document registry; skel default-app lists drift across editions.
Stale: "Files can't drag out" is false — FilesPanel.qml:863,985,1197 does drag out.

## Multi-user, family, guest, enterprise/MDM

Already built: per-user settings/screen-time, app blocking via malcontent, guest on/off, usershares, current-grants privacy dashboard, fleet agent with inventory/signed remote exec.
Feasible gaps: screen time advisory only (no enforced caps); no bedtime/downtime schedule; no weekly/monthly report or export; parental filter set outside shell; no approval/ask-a-parent flow; no per-user web/content filtering; no privacy access timeline; no bulk revoke/app-data deletion; no "why does this app need X" rationale; no simplified/caregiver mode; guest has no rules; no kiosk/single-app mode; no settings-profile copy between accounts; no child-visible weekly digest.
Needs server/daemon: MDM enrolment/policy plane, remote wipe/lock, signed configuration profiles, per-user certificate management, enforced signed settings, trustworthy access log, cross-account parental supervision, guided access/switch control, family account layer (CalDAV/CardDAV/IMAP services), enterprise inventory surface.

## Hardware and peripheral depth

1. **[H×M]** Bluetooth codec choice (LDAC/aptX/AAC/SBC) — no org.bluez.MediaTransport1 reference anywhere.
2. **[H×M]** USB device blocking — no usbguard reference.
3. **[H×M]** General key remapping/layers — InputConfig.qml:15-32 writes only xkb options.
4. **[H×M]** Per-app camera/mic permission for native apps — SettingsAppPermissions.qml governs Flatpak portals only (partly OOS).
5. **[M×E]** Camera hardware privacy switch state — Privacy.qml:17-20 infers from kernel module, not actual switch/LED.
6. **[M×M]** Camera controls (focus/exposure/zoom/pan/tilt) — Camera.qml:87-89 uses cam only to select index.
7. **[M×M]** Microphone AGC/gain — SettingsSound.qml:273-280 only RNNoise toggle.
8. **[M×M]** Audio loopback — no module-loopback/null-sink in shell.
9. **[M×E–M]** Per-app power profiles — GameMode.qml:26-29 hardcodes fullscreen game → performance.
10. **[M×E]** Thermal sensor depth — SysStats.qml:119-122 reads single CPU hwmon.
11. **[M×E]** EDID/panel info — Displays.qml:238-239 keeps only make/model/physical mm.
12. **[M×E–M]** Extended printer options — SettingsPrinters.qml:189-191 hardcodes media/duplex/colour.
13. **[M×M]** Bolt device management UI — Thunderbolt.qml:23-37 enumerates/prompts on arrival only.
14. **[M×M]** UPS depth — bridge/ups.py:35-51 reports only first UPS and six variables, no graceful shutdown.
15. **[L–M×M]** Per-sink audio delay (lip-sync) — Audio.qml no latency property.
16. **[L×E]** Sound theme/scheme — SystemSounds.qml:13 hardcodes freedesktop path.
17. **[L–M×M]** Named multi-monitor arrangement profiles.
OOS: virtual displays, overscan, mouse accel threshold, fan curves, USB gadget modes, per-output HDR/gamma/colour filters, Sticky/Slow/Bounce Keys.

---

# Third pass — full reports

## Unaudited utility apps (agent)

Archive Manager: gaps delete/rename member, route .jar/.apk to zipadd, open member in own app, integrity test, add to 7z/rar/ISO, progress, comments. Bugs: appendable includes jar/apk but branch uses zipadd only for zip; zipadd.py stores ../outside.txt for files above archive folder; zipadd.py names no caller.
Calculator: gaps DEG/RAD/GRAD, variables+Ans, mod/integer division, hyperbolic, log(x,base), history persistence, currency/date conversions, copy expression. Bugs: Ui.calculatorTab written but never read at startup; Base ▸ button inert (baseOutputs renders all four); charCode uses UTF-16 charCodeAt(0) vs fromCodePoint.
Clocks: gaps weekday repeat/one-shot/snooze/sound, ringing panel, custom timers/multiple, per-lap deltas, in-app city search, sunrise/sunset, state persistence, shortcuts. Bug: lastFired single minute string so alarm added for already-fired minute silently missed.
Characters: gaps browse starts at ASCII punctuation not symbols/scripts, favorites/recents, Unicode-block browsing, insert-into-last-app, multi-codepoint emoji skipped, copy as U+/HTML/decimal, glyph detail, font preview. Bug: characters.py:203 claims browse shows symbols first but returns entries[:limit].
Fonts: gaps family/style search (400-style cap), uninstall, drag-and-drop, license/glyph grid, .ttc face list, Settings handoff, side-by-side, recents. Bugs: percent-encoding in install path (FIXED), installFont silently overwrites.
Maps: gaps limit=1 geocoding, transit, live traffic, offline maps, map style, typed start marker/waypoints, reverse geocoding, alternative routes, keyboard pan/zoom. Bug: routeUrl always uses Location ignoring typed fromLat/fromLon (FIXED).
Disk Usage: gaps Rings chart, scan progress, exclude config, in-app chooser, hardlink double-count, preview, used/free bar. Bugs: dir_size walks every subtree synchronously per child; enter()/back() don't clear marked (FIXED).
Document Scanner: gaps batch/duplex, post-scan crop/rotate, page reorder/merge, scan-to, scan-area, per-device options, OCR, history. Bugs: scanErr collected but never displayed; --resolution not universal SANE option.

## Communication/apps (agent)

Logs: "Show raw entry" button closes details; priColor() defined never used; no priority/unit/boot filters; fixed -n 200; no export; search misses PRIORITY fields; no new-error notification.
Password Generator: no exclude look-alikes, custom length, word count, entropy readout, save to keyring, GPG actions, clipboard auto-clear. RNG sound (secrets); wordlist missing silently emits random string.
Authenticator: UI cannot set digits/period/algorithm (bridge can); no edit/rename; no export/backup (lost keyring loses all tokens); no search/sort; no icon; clipboard not cleared; refresh tick can miss rollover. Secrets in GNOME Secret Service (good).
Nearby: cancel unwired (FIXED), text sharing, no persistent trust store, fixed receive location, rename, history, folder send. Security: TLS CERT_NONE, fingerprint from unauthenticated multicast.
Converter: fade/artist/speed unwired (FIXED), per-job options wrong, output-folder choice, metadata strip, no cancel. Invalid numbers silently coerced.
PDF Signer: only current page saved — one-page PDF destroys rest (FIXED); no real cryptographic signature; no drag-to-place; no rotation/opacity/multi-signature; no AcroForm fill; no placement undo.
Kundali: timezone always UTC (appends Z) — wrong Lagna (FIXED?); nine bridge commands unwired; no visual chart; no city search; no export/history; hardcoded Lahiri; malformed ISO with seconds.

## Messages/Calls/Phone (agent)

Architecture: GTK4 shani-link owns Messages/Calls; QML shell has entry points and modem dialog.
Gaps: conversation search; inline Reply on text notifications; group threads; image attachments; SMS backup/export; drafts; speed dial/favorites in shell; call-waiting UI; tie recordings to caller; delivery/read status.
Security: messages not E2EE, bodies echoed to notify-send; positive: bidi control chars stripped, switches default off.
Dead: PhonePanel.add_tab() empty stub; openRecentCalls() opens Calls tab.
Impossible: real SMS/voice without modem/paired phone; iMessage/FaceTime/RCS; typing indicators/read receipts/reactions; visual voicemail; E2EE for SMS; MMS picture receive.
Already built: call history with duration, hold/swap/merge landline, two-sided recording with consent, SMS OTP copy and Reply.

## Missing app categories (agent)

18 categories: Podcasts (Q), audiobook mode (Q), IRC (Q), database client (Q), teleprompter (Q), network tools (Q), health/fitness (Q+D), startup manager (Q), scheduled tasks (Q), offline dictionary (Q), VPN client (partial), cloud storage (D/S), system restore (partial), video conferencing (WebApp), e-book reflow (partial), NFC (H), Emergency SOS (S+H).
Out of scope: Find My, wallet/payments, iMessage/FaceTime/iCloud, native app store, browser/office/torrent/VM/games (Flatpak-only), remote desktop control, NFC/SOS.

## Accessibility (agent)

"Accessible by default" overstated. 20 gaps: no live regions; custom controls no AT-SPI name/role; slider value not exposed; verification claim thin; Super+Alt+S absent in running session (FIXED); Theme.faint fails AA; accent on accentSoft fails AA; captions not accessible output; error message claim overstated; muted state colour-only; touch targets inconsistent; no continuous text size; no focus traps; Escape missing in Mail/Feeds/Processes; no headings/landmarks; focus ring 1px colour swap; IME hints only for secrets; no RTL mirroring; one unguarded animation; app-menu AT-SPI best-effort.

## Security/i18n/ecosystem (agent)

Security: hook placeholder injection (FIXED), QR world-readable path (FIXED), files.py chmod follows symlinks, WebApps safeUrl undefined (FIXED), stale desktop entries glob quoted, SettingsPage fake chips (FIXED).
i18n: greeter no translation, two catalog systems, English plural via %2, no placeholder parity validation, 83 unwrapped literals, two substitution mechanisms.
Ecosystem: no CONTRIBUTING, no IPC reference/stability contract, no man page/completion, undocumented LauncherEntry D-Bus, settings pages hardcoded, no theme-pack API, no CI config.

## Capture tools (agent)

Screenshot: region/window capture, all-monitors, history browser (encrypted captures never listed), OCR preview, configurable dir, pin zoom/fit. Bugs: PinCapture claims move/resize but fixed window; scroll-capture manual mode documented but absent.
Recorder: pointer toggle, delay, single-window, container choice, cancel, max duration, mic meter.
Color Picker: no picker window, recents never rendered, colour wheel, copy-as formats, sample from image. Bugs: claimed clipboard copy never happened (FIXED), picked signal no listener, dead code!=0 branch.
Ruler: ratio never assigned (FIXED), diagonal/angle, ticks, saved measurements, units, arrow nudge, loupe. Bugs: dead straight property, grim captures all outputs vs one screen, temp PNG never deleted.
Lens: QR action types beyond http/copy, OCR language choice, editable OCR text, TSV structure, history, keyboard region. Bugs: save hardcodes .png for jpg, openImage no encoding, language regex.
Magnifier: auto-refresh, full-screen mode, inversion, resizable, arrow pan, reset key, cross-monitor.
Captions: history/scrollback, pause/resume, timestamps, font settings, send to Chronoa, language picker. Bug: hh-mm 12-hour filename (FIXED), out-of-order captions.
Tour: five raw literals not Tr.t, tourEnabled checked only in shell.qml, no spotlight/capture card/try-it/replay/Back.
Preview: PDF navigation/zoom, metadata, archive extract-one, video seek, share, image zoom/pan; Viewer redo/fullscreen/copy pixels. Bug: PDF cache key md5(path) only (FIXED).

## New apps and session surfaces (agent)

Backup: two restore buttons identical (what/restoring dead); CLI restore into new folder only; no progress/cancel, JSON errors swallowed, no verification badge, retention/exclusions/off-site/diff.
Models: API keys never stored (FIXED); download announces success on failure and notifies per line; preferred model set before success; GGUF claim false; VRAM unused; no live registry/test-connection/in-window errors.
Studio: busy never cleared (FIXED); find expression can never match .desktop under ~/Developer so gio launch dead; no code preview/revision/syntax check/export/privilege warning.
Firewall: newZone/deleteZone use --permanent without --reload; parseZones drops hyphenated keys; interfaces/target parsed but not displayed; presets English; no panic mode/logging/validation.
Passwords: audit never ran (FIXED); passkey copy wrong field; passkey-add false success; FIDO2 no commands; locked collections invisible; attribute editing, GPG expiry, import/export, generator handoff.
Greeter: typed password kept on user change (FIXED); no translation, IME, auth status, last-layout, user dconf a11y, PIN path, retry countdown.
Setup: 1-char password (FIXED); Chronoa setting written from greeter user; auto-join open Wi-Fi without asking; onAuthMessage answers every prompt with password; no hidden Wi-Fi/proxy/restore/encryption/import/telemetry.
Lock: messages raw English; photos accumulate but only newest shown; biometric unlocked() outside password conversation; queued discarded; no session-level lock test.

---

# Second pass / Deep verification — full reports

## Editor/Notes/Calendar/Contacts deep verification

Text Editor: smart indent/bracket close missing; regex/case/word search missing (HighlightText.qml unused helper); MRU switcher missing; current-line/brace highlight missing; bookmarks missing; word/char count missing; split view + session restore missing.
Notes: Markdown preview missing; trash/restore missing (rm -f); version history missing; formatting toolbar missing; tags missing; to-dos with due dates partial; previews/sort partially implemented (preview() used in SidebarNotes/Launcher, gap text wrong); body search partial.
Calendar: description missing; detail popover missing; quick-add missing; ICS import button missing; repeat missing; alarms missing; drag create/move missing; current-time line + local calendar CRUD/colour missing.
Contacts: multiple phones/emails partial (backend arrays, UI single); detail sheet missing; QR export missing; avatars missing; favorites missing; index/sort partial; manual link/unlink partial.
New bugs: Notes "Lock" calls nonexistent subcommand (FIXED); Contacts merge destroys phones/emails (FIXED); Calendar edit drops RRULE (FIXED); Contacts setGroups/setSelf drop arrays (FIXED).
New gaps: TextEditor no Ctrl+G UI; TextMate theme not persisted; Calendar per-event timezone display-only; Contacts no export all; Notes no vault import/backlinks/spellcheck; Calendar no read-only banner.

## Files/Photos/PDF/Mail/Feeds deep verification

Files: search filter popover missing; breadcrumb dropdowns missing; visible columns missing; select-matching partial (FileFilter.js exists, no action); symlink missing; grid captions missing; sort Type/Date Created missing; second window OOS. Undo/redo already built (gap was wrong).
Photos: filter chips inert (FIXED); delete tile partial; multi-select missing; sort partial; slideshow partial; EXIF partial; ratings/tags missing; date-subfolder import missing.
PDF: bookmarks missing; clickable links missing; attachments missing; history/first-last missing; two-page missing; annotations list partial; search options missing; print range missing; merge/split no UI; radio widgets unrendered.
Mail: Reply/partial; date+snippet partial; Cc/Bcc missing; save attachments partial; mark unread/star/archive partial; view source missing; remote images missing; multiple accounts missing; conversation threading missing; labels missing.
Feeds: summary partial; next-unread/mark-all partial; tags missing; search missing; bookmark missing; show-read partial; auto-discovery missing; enclosures missing; query feeds missing.
New gaps: PDF merge/split no UI; form radio widgets; Files previewer actions; gthumb catalogs; Viewer drops zoom on next image.

## Terminal/Disks/Software/Processes/Settings deep verification

Terminal: -R/-D missing; import/export hosts missing; advanced options missing; recents/status missing; remote shell integration OOS. Test connection and import key unwired (FIXED).
Disks: allocation bar missing; detailed SMART/self-tests missing; partition management partial; image tools already implemented elsewhere (gap wrong); unlock/passphrase already implemented elsewhere (gap wrong); job progress partial; mount options missing; benchmark missing; take-ownership/detach missing.
Software: ratings missing; featured missing; apt/dpkg/Snap OOS; version history missing; screenshot gallery partial; repository management partial; add-ons missing.
Processes: sort missing; signal choice missing; details dialog missing; renice/affinity missing; Users view missing; columns/meters missing; saved views missing.
Settings: Online Accounts OOS; ICC OOS; WWAN mostly implemented (only data cap missing); removable media missing; Wacom partial; driver/firmware OOS. Fractional scaling and per-monitor wallpaper/scale already implemented (gap wrong).
New gaps: process tree broken (ppid dropped, FIXED); no load/swap/PSI meters; SMART self-tests; take-ownership; EOL warning; screenshot carousel; DNS search domains; text-size slider; primary SIM slot.

## Media/Camera/Voice/Trimmer/Translate/Weather deep verification

Media Player: EQ missing; goto-time/chapters missing; A→B loop missing; video effects missing; recent media partial; network stream partial (playStream exists); save/load m3u partial; record missing.
Camera: QR mode partial (post-capture only); self-timer missing; composition grid missing; shutter sound missing; audio toggle missing (FIXED); H.264 missing (partly); picture format missing (partly); in-window gallery partial.
Voice Recorder: waveform partial; format/stereo missing; export missing; skip back/forward missing; names/duration partial; cancel missing; in-app playback missing; peaks missing.
Video Trimmer: timeline missing; multi-segment missing (later FIXED); I/O/S shortcuts missing; detection missing; keyframe snapping partial; capture frame missing; speed/mute missing; remux missing.
Translate: source pick missing; file/HTML missing (later FIXED); model status missing; pivot OOS; batch partial; history OOS.
Weather: multiple locations missing (later FIXED); temperature graph partial; dayparts missing (later FIXED); precipitation/wind missing (later FIXED); sunrise/sunset done.
New gaps: camera picker cosmetic (FIXED); no gallery delete; MPRIS HasTrackList False; no Stop control; trimmer overwrites prior output (FIXED); no cut progress; Translate endpoint UI; Weather capped 7 days.

# First pass — documented in shani-shell/docs/GAPS.md

The first pass (app-by-app vs upstream OSS equivalents, shell-surface vs GNOME/KDE/macOS/Slate, and infra/docs audits) is preserved in the main GAPS.md sections:
- "Full upstream app comparison — every gap found (Nov 2026)" (20 apps, 158 gaps)
- "Second-pass deep audit (Nov 2026) — corrections, new gaps, shell and infra"
- "Third-pass audit" sections
- "Fourth-pass research", "Fifth-pass research", "Sixth-pass research", "Seventh-pass research"

The first-pass subagents compared: Text Editor→Kate, Notes→Joplin, Calendar→GNOME Calendar, Contacts→GNOME Contacts, Files→Nautilus, Photos→gthumb/Loupe, Viewer/PDF→Evince, Mail→Geary, Feeds→Newsboat, Terminal→kitty, Disks→GNOME Disks, Software→GNOME Software, Processes→htop, Settings→GNOME Settings, MediaPlayer→VLC, Camera→GNOME Snapshot, VoiceRecorder→Vocalis, VideoTrimmer→LosslessCut, Translate→Argos, Weather→GNOME Weather. Each produced 5-8 ranked gaps with implementation sketches; all were transferred into the curated GAPS.md and the implementation passes. The three doc-audit agents (shani-shell, shani-docs, infra repos) found stale counts, wrong paths, false plugin claims, edition/provider/sync-direction errors, and workflow profile/timeout/secret errors — all fixed in commits 28c49e5, 1a585ab, 8b18653, 3d5da6b, 80139eb.

All reports in this archive are static findings — no runtime or hardware verification was available.

---

# Eighth pass — full reports

## Non-technical user documentation & UX (agent ses_dfbc6e71dffeTNRTzzZ72zWWxo)

Read: overview.md, faq.md, troubleshooting.md, intro/*, install/*, system/{printing,backup}.md, updates/shani-reset.md, whats-new.md, setup/shell.qml + strings.js, bridge/QML error strings, index.html. Static only. Prior-pass fixes skipped.

A. Task orientation & onboarding (highest value):
1. (H/H) No "how do I…?" entry point. overview.md:120-133 "How to Use This Wiki" is a table of internals — "Concepts… Architecture deep-dives", "Boot process, Btrfs layout, dracut". A person asking "how do I connect a printer / back up my photos / share files / set up email" has no landing page. Fix: add a "Common tasks" card list linking existing system/printing, system/backup, networking/samba, servers/mail pages.
2. (H/H) First steps are all terminal commands. intro/getting-started.md:104-158 "Recommended First Steps" = add Nix channel, gen-efi enroll-tpm2, shani-deploy, flatpak install, waydroid init. Fix: lead with "open Software and search for an app"; label every terminal step "optional / advanced".
3. (H/H) "How do I install an app?" never names the GUI first. faq.md:43-50 answers with flatpak install, nix-env, distrobox create, podman run. Fix: first line "Open the Software app and search — that is the normal way"; keep CLI below.
4. (H/H) Bug reports are developer-only. faq.md:332 "include the output of uname -r, cat /etc/shani-version, cat /data/current-slot, and relevant journalctl logs"; troubleshooting.md:681-690 repeats. Fix: "tell us what you were doing and what you saw; attach a screenshot — or copy diagnostics from Cassini".
5. (H/M) Encryption choice explained as internals. install/steps.md:18 "Enable LUKS2 full-disk encryption (argon2id key derivation)". No consequence, no "can't change later". Fix: "Encrypt my files (recommended for laptops) — if the laptop is stolen, nobody can read your files. Remember the password; it cannot be changed later without reinstalling."
6. (H/M) Setup wizard omits encryption entirely. setup/shell.qml:36 pages are welcome,keyboard,network,time,account,chronoa,done; setup/strings.js has no encryption strings. Fix: one plain-language summary line on account/done page: "Your files are/are not encrypted; change requires reinstall."
7. (M/H) Chronoa and account ARE explained well — the bright spot: strings.js:13 "It runs on your own computer, with no cloud and no cost. Turn it off if you prefer"; :31 "This account… can install software and change system settings." Use as template for 4-6.

B. Troubleshooting written as developer notes:
8. (H/H) Fixes are command dumps, not "if X do Y". troubleshooting.md:28-49 "System Won't Boot" opens with six commands before telling the user the system usually recovered itself (stated at :30). Fix: lead "If the screen stays black after an update, reboot once — it usually fixes itself."
9. (H/M) Unexplained TTY. troubleshooting.md:81 "Switch to a TTY (Ctrl+Alt+F2 or F3) and log in". Fix: "Press Ctrl+Alt+F2 for a plain text login screen (Ctrl+Alt+F1 returns)."
10. (M/H) "If X, do Y" is used in places — copy that pattern. troubleshooting.md:291 and first-boot.md:78-87 symptom table are the right shape; most other sections are not.
11. (M/M) Engineered correction note. troubleshooting.md:70-74 "There is no shani-deploy --repair-boot…" useful but speaks flag names; no GUI alternative.
12. (M/M) Developer-speak fingerprint answer. faq.md:241 PAM services / pam_fprintd. Fix: "On GNOME your fingerprint works at login; on KDE only at the lock screen; on COSMIC it is not available yet."

C. Jargon without plain-language gloss:
13. (M/H) Security section opener. overview.md:22 "Six Linux Security Modules run simultaneously (lsm=landlock,lockdown,yama,integrity,apparmor,bpf)… Intel ME kernel modules not blacklisted by default". Fix: one sentence "These are independent locks on the system; a fault in one does not open the others."
14. (M/H) Navigation table aimed at newcomers. overview.md:129 "Security | Polkit tiers, LUKS, TPM, AppArmor, Secure Boot, audit, hardening". Fix: "Password rules, disk encryption, fingerprint and secure boot."
15. (M/H) D-Bus / AT-SPI unexplained. overview.md:76 and faq.md:147. Fix: "the top bar reads the app's own menu" (keep protocol names in parentheses).
16. (M/M) Jargon wall before simple steps. system/printing.md:13-15 opens with CUPS, ipp-usb, eSCL/AirScan, WSD, SANE, cups-pk-helper, then only at :20-26 says "Settings → Printers → Add Printer". Fix: move GUI steps to top.
17. (M/M) Backup jargon. system/backup.md:138 restic; GUI alternative at :13 buried. Fix: promote :13 to opening.
18. (L/M) Printing permission note. system/printing.md:87 cups-pk-helper gates via Polkit. Fix: "Adding a printer asks for your password — that is normal."

D. Step completeness, safety, product errors:
19. (H/H) Destructive restore with no warning. system/backup.md:95-98 "sudo btrfs subvolume delete /home" — deletes today's files, said nowhere. [FIXED in this pass: added warning]
20. (M/H) Factory reset leads with mechanism, not consequence. updates/shani-reset.md:9. Fix: open "This deletes your accounts, Wi-Fi passwords, and — with --home — every personal file. Back up first. It cannot be undone."
21. (M/M) Wrong-slot recovery lacks plain outcome. troubleshooting.md:58-74. Fix: repeat "your files are safe; only the OS version changes" in-section.
22. (M/M) Raw backend errors reach users. PasswordsWindow.qml:69 raw JSON error; SoftwareWindow.qml:203-207 flatpak text; bridge/cleanup.py:122,146; bridge/live-tv.py:306. Fix: small string maps.
23. (L/M) No glossary anywhere. index.html has good a11y and no screenshots in docs, but no term-definition page. Fix: docs/glossary.md linked from Quick Links.

## Shell startup, shutdown & session lifecycle (agent ses_dfbc79244ffeZt23SnpoKilMY4)

Static only. Skipped prior-pass items.

Shell-fixable:
1. Shell-internal long jobs don't inhibit idle suspend. Idle.qml:97-101 only honours ext-idle-notify/ScreenSaver inhibitors; Files.qml:534,676-680 schedules suspend after copy drains, Recorder.qml:94-102/convert.py run ffmpeg with no inhibition. Idle Power.suspend() can cut copy/conversion/download mid-write. Sketch: inhibit when _jobs.length>0 || VoiceRecorder.recording || Convert.busy.
2. Debounced state writes lost on immediate logout/poweroff. PlayQueue.qml:48-72 resume flush 1500ms; VoiceRecorder.qml:49-55 counter 800ms; Power.logout/poweroff/reboot (Power.qml:223-225) fire systemctl/niri quit with no flush. Sketch: Session.flush() IPC.
3. No "save your work"/app-close prompt on logout/reboot/poweroff. SidebarHeader.qml:216-227 single double-click "Sure?"; Ui.closeAll() closes panels not windows; TextDocs.qml:29 exposes unsaved that nothing consults. Sketch: gate Power.* on dialog listing dirty apps.
4. Recorders/conversions never finalised at session end. Recorder.stop() SIGINT (Recorder.qml:69-76), VoiceRecorder.stop() (90-105); on logout neither called, Opus/MP4 containers stay open.
5. No resume handling at all. logind.py:66-72 re-inhibits on PrepareForSleep(false); Lock.qml:28-42 has no resume op. Media not paused/restored, BtAgent.reconnect() (BtAgent.qml:50-60), display/wallpaper not re-applied, no network re-check.
6. No shutdown/logout hook for user scripts. Hooks.qml has startup + lock/unlock hooks but no session-end event.
7. UPS "save your work" is a dead-end toast. Ups.qml:52-54 no countdown, "shut down now" or deferral.
8. Power confirmation hides its scope. SidebarHeader.qml:216-227; lock screen armed 4s button (LockScreen.qml:280-294). Neither shows how many apps/unsaved docs will be lost.
9. Suspend can hang if no output covered by lock. Lock.qml:15,26 releases sleep delay only once secure set by WlSessionLock covering every output; headless resume flag never flips.
10. Other logind sessions invisible. greeter/shell.qml:104-120 only probes /run/user/<uid>; no session list, "log out other user", multi-user awareness.

systemd/compositor-level:
11. No startup readiness for niri/audio/network/keyring/Chronoa. shani-shell.service:5-9 only After/Requisite=graphical-session.target; no After=niri.service. Dev session waits for every daemon (dev/session.sh:115-241). Slow deps produce reconnect timers and blank first frame. Sketch: add After= lines + "Starting desktop…" cover.
12. shani-chronoa-bridge.service has no dbus ordering (chronoa-bridge.service:1-12).
13. No user-session stop protocol. Logout is niri quit --skip-confirmation; no org.gnome.SessionManager/XSMP equivalent, so external apps cannot veto/save. Compositor-level.
14. Restart=on-failure only; no success-exit semantics/watchdog (shani-shell.service:21-22).
15. Sleep inhibition covers only sleep, not shutdown (logind.py:98).

Comparison: GNOME Session tracks inhibitor clients + EndSessionDialog; KDE ksmserver per-app save-then-quit; macOS applicationShouldTerminate:; Windows WM_QUERYENDSESSION. ShaniOS has a two-click "Sure?" and systemctl.

## Latest releases (2024-2026) comparison (agent ses_dfbc74427ffeaP772aSwHXc92l)

Verified candidates against tree (Writing Tools, long-press quick tiles, Live Activities, blur/glass, focus app-allowlist, named-panel ideas already built/filed — excluded).

1. Named, on-demand sessions (KDE Plasma 6). Reopen.qml:33-58 keeps one automatic last-session list, offered only at sign-in. Sketch: "Save session as…" named JSON of desktop ids + workspace.
2. Recall-style activity timeline (Win11). Screenshots encrypted captures never listed; Chronoa meaning index file-oriented, no time axis. Sketch: rolling local grim thumbnails + OCR text timeline.
3. Private Space — hidden locked app vault (Android 15/16). AppFilter.qml is parental blocking only. Sketch: "Move to Private Space" gated behind Keyring/PIN via Polkit.
4. On-screen contextual action overlay (Win11 Click to Do / Apple Visual Intelligence). Lens.qml does region OCR/QR/translate/ask-Chronoa, no element-level actions. Sketch: action chips after Lens capture.
5. Unified Recent-files hub (GNOME 48 Files). Apps never write recently-used.xbel; Launcher recents one-way. Sketch: shell writes XDG recents + "Recent" launcher section.
6. Customizable lock-screen shortcuts (iOS 18). Fixed camera (LockScreen.qml:350-393) and power; no torch, not configurable. Sketch: two Settings pickers.
7. Focus Filters depth (iOS 18). Focus.qml:23-25 only gates notifications by app name. Sketch: people/calendar/badge filters.
8. Notification cooldown (Android 15). No cooldown in Notifs.qml; distinct from storm coalescing. Sketch: per-app last-seen timestamp, downgrade Nth repeat within ~10s.
9. Lock-screen widgets (iOS 16+). Lock surface only notification/media/camera (LockScreen.qml:340-409). Sketch: render one/two existing widget delegates.
10. Cross-device clipboard continuity (Apple Universal Clipboard). Clipboard.qml local; shani-link can share but leaks with no confirm. Sketch: opt-in push with confirm card + 45s clear.
11. Instant replay / rolling record buffer (Xbox Game Bar / ShadowPlay). Recorder no rolling buffer. Sketch: background wf-recorder to ring file, hotkey promotes last N seconds.
12. Rotating widget stacks (macOS Sequoia / Win11 Widgets). desktop-widgets-* built, no stacking. Sketch: auto-rotate timer + manual swipe.
13. Auto-arrange desktop icons (Finder Sort By). DesktopIcons.qml has placement, no sort action. Sketch: right-click "Arrange By…".
14. Camera studio effects — background blur / centre framing (macOS Studio). Camera.qml only picks device index. Needs PipeWire/OpenCV filter chain.
15. Per-focus app-badge suppression. Focus.allows() only used by notification path (Focus.qml:23-25). Sketch: reuse allow-list in Launcher badges and LockScreen.

Out of scope: Stage Manager, predictive-back gesture, AOD/raise-to-wake, Windows Hello enhanced, Genmoji/Image Playground/cloud Recall, remote desktop control, Live Text on video, Wi-Fi sensing/theft-detection, HDR/colour filters/gamma, trackpad gestures, Find My/SOS/carrier.

## User data lifecycle (agent ses_dfbc7ba6dffe53ahJHhqmVUehs)

Scope: shani-shell bridges/services + shani-chronoa + shani-insights stores. Skipped prior-pass categories.

Control matrix (V=view · 1=delete one · A=delete all · R=retention · E=export) — 25 stores including Notes (.trash/.history; no delete-all, 20/note only, ~export), Contacts (.vcf; export yes), Agenda/EDS (import only), Feeds (OPML subs only), Mail (server-side, no export), Photos meta.json/albums.json (no delete-all/export), Music library.json (KEEP, no delete), ScreenTime (5 wks, no clear/export), Notif history (50-cap, delete-all yes), Screenshots+.age (none of V/1/A/R/E), VoiceRecorder (export yes), Captions transcripts (none), CallRecorder (none), Call logs (view only), Chronoa transcript (in app, append-only), Chronoa learned bandit.json/outcome-*/tool_calls.log (none), AI provider keys, Models, Terminal hosts/snippets, WebApps, recents, Logs, Backup snapshots, Passkeys/OTP, U2F (delete all only).

Ranked gaps:
A. Deletion correctness:
1. Contacts merge destroys almost every field — Contacts.qml:200-216 rewrites via edit payload; contacts.py:481-516 rebuilds fixed dict. Avatar, favorite, self, groups, unknown vCard fields lost from both cards. Fix: merge at vCard property level.
2. Notes private trash/history escape retention sweep — QuickNotes.qml:49-50,339-341; Housekeeping.qml:14-24 only walks XDG Trash/info.
3. Deleting a note orphans its version history — remove() (QuickNotes.qml:293-324) moves only .md; .history/<id>-* copies stay forever.
4. Notes cloud sync leaks trashed/encrypted-adjacent copies and never applies deletions — rsync -au (QuickNotes.qml:71) copies hidden .trash/.history, no --delete.
5. Call recordings have no lifecycle surface — CallRecorder.qml:17-30 writes .ogg and only notifies path; no list/play/delete/TTL/export.
6. Caption transcripts accumulate unmanaged — Captions.qml:18-19,46.
7. Screenshot .age files no retention/delete-all — encrypt-capture.py:35-50.
8. Photos metadata sidecars survive photo deletion — path-keyed, never purged.
9. U2F can only forget every key — SettingsAccount.qml:420 → u2f.py:101-113 drops whole file.
10. Cleanup cannot free any app data store — cleanup.py:34-39 marks shani-shell/cliphist/Chronoa caches KEEP.
B. GDPR/data-subject:
11. No "show me all data the shell holds about me" — SettingsPrivacy.qml:164-184 only recents/trash/clipboard toggles.
12. No "forget me" for a single app.
13. No retention setting for any user-data store — only hard-coded values (trashDays 7/30, downloads 90d, ScreenTime 35d, notifs 50, notes 20/note).
14. ScreenTime history cannot be cleared or exported.
15. Launcher usage profile invisible — app-usage.json (Launcher.qml:108-120) no view/reset.
16. Portal grants have no per-app data footprint view.
C. Memory/learning:
17. Chronoa learned state unviewable/unforgetable — learning.py:5625 bandit.json, :1885 tool_calls.log, :4566 outcome-predictions.jsonl.
18. Transcript grows without bound — conversation_store.py:38-44 append-only; MAX_LOADED=500 read cap not truncation; backend clear()/delete() have no shell caller.
19. "Forget these answers" only in Chronoa GTK settings window (activity.py:571-581).
D. Telemetry:
20. No shell-side inventory of what is collected — shani-insights opt-in collector gathers app/window activity, optional tab URLs, cam/mic device names, screenshots, session recordings; self-service view only on server.
21. No retention statement for diagnostics — problem reports printed not stored (good), but no user-facing page states "we keep none".
Highest value × ease: #5, #6, #2, #3, #14, #15, #19. Hardest: #1, #12/#20.

## UX consistency and tone (agent ses_dfbc76949ffeYbYOdu4qgBiU3e)

22 inconsistencies, ranked. Skipped prior-pass items.

Terminology:
1. "Log out" vs "Sign out" for same Power.logout() — SidebarHeader.qml:206, Ring.qml:84, LauncherActions.qml:97 "Log out"; TvHome.qml:73 "Sign out"; shell.qml:107 "sign out". Canonical: "Log in/Log out".
2. "Devices" vs "Drives" for storage — FilesPanel.qml:521 "Devices"; SidebarDrives.qml:24 "Drives"; DisksWindow.qml calls disk "device"/"block devices". Canonical: "Drives" storage, "Devices" peripherals.
3. "Delete" for recoverable trash — SidebarNotes.qml:198 "Delete this note" calls remove() which moves to .trash; CameraPanel.qml:187; FeedsWindow.qml:112 "Remove"; but NotesPanel.qml:450 and FilesPanel.qml:3111 "Trash". Canonical: "Move to Trash" recoverable, "Delete" permanent.
4. Notebook vs folder in Notes — low priority.
Errors:
5. Developer-grade bridge errors rendered verbatim — 32 QML sites root.error = r.error; bridges return lowercase CLI internals (link.py:309 "usage: link.py…", files.py:533 "already exists", passwords.py:290 "no such key", flatperm.py:137 "not a permission: %s"). Canonical: bridges return {code,message}; QML owns user-visible text.
6. Command names/shell syntax leak — SettingsSharing.qml:157 "sudo setcap cap_sys_admin+p $(command -v sunshine)"; Files.qml:1307 "rsync exited %1"; Disks.qml:166 "is lsblk installed?"; QuickNotes.qml:718 "is gpg installed?". Canonical: "This feature needs X" + action; command in "Copy details".
7. Raw stderr appended — Archive.qml:187,235,297,354,382, Tasks.qml:67, Disks.qml:203, Contacts.qml:238, SettingsStorage.qml:54, flatperm.py:141,157, ratbag.py:121 use stderr last line.
8. Actionable vs cryptic, no template — good: MapsPanel.qml:242,245,654,661; cryptic: Feeds.qml:131 "The feed reader could not answer", Link.qml:87, VoiceRecorder.qml:297 "Export failed", Backup.qml:114 "Backup failed", Firewall.qml:163.
9. Case/tone split — QML sentence case; bridge lowercase.
10. Greeter/setup show raw PAM text — greeter/shell.qml:214; setup/shell.qml:330,1288.
Loading/progress:
11. Ten words for busy — "Looking…" (9 files), "Scanning…" (3), "Working…" (4), "Loading…", "Searching…", "Computing…", "Comparing…", "Counting…", "Measuring…", "Cleaning…". ScannerPanel/DiskUsagePanel each use two words for same state. Canonical: "Scanning…" enumeration, "Working…" generic.
12. Spinner only on buttons — Common/Spinner.qml wired through Button.qml:78; ~24 text-only busy labels no indicator.
Empty/success/confirm:
13. Four title grammars — "No X yet", "No X", "Nothing X", "This folder is empty". Canonical: "No <plural> yet" first-run, "No <plural>" filtered.
14. Errors disguised as empty states — FilesPanel.qml:1046, ArchivesWindow.qml:215, AuthenticatorWindow.qml:208 render via EmptyState with faded icon.
15. Three success channels no rule — toast (SettingsPage.qml only), inline notes, notify-send. PdfSigner does both at :186 and :188.
16. Success notifications bypass i18n — VoiceRecorder.qml:160, Camera.qml:204, Calculator.qml:640, Modem.qml:77, Ruler.qml:81 bare literals.
17. "Click again" vs "Tap again" even in one file — DisksWindow.qml:152,171,215,261,291 vs :446. Canonical: "Tap again".
18. Three confirmation mechanisms — two-tap, modal, type-to-confirm.
19. Missing confirmation on irreversible deletes — CalendarPanel.qml:1319 Delete → EDS no undo; MailWindow.qml:304 → IMAP. Canonical: two-tap both.
Shortcuts/icons:
20. Zoom modifier mismatch — FilesPanel.qml:100-104/TextEditorPanel.qml:442-444 Ctrl++/Ctrl+0; PdfReader.qml:238-240 bare +/-/0.
21. Bare W means different things — Ctrl+W close tab (TextEditor, Files); bare W fit width (PdfReader); bare Q close window (Switcher:134); global Mod+Q close-window.
22. Same "Move to trash" two icons — edit-delete in FilesPanel.qml:3111/Viewer.qml:471 vs user-trash in PhotosWindow.qml:418, TasksWindow.qml:225, StudioWindow.qml:139, ModelsWindow.qml:126, ContactsWindow.qml:442, FilesPanel.qml:508. Canonical: user-trash recoverable, edit-delete permanent, edit-clear-all bulk.
Skipped: ellipsis glyph consistent, no OK/Apply, app-menu help/empty-state actions covered pass 7.

## Calls, Messages, Link, Phone/Modem, Gamescope (agent ses_dfbc6bce0ffegr7r1O8sPNcyVa)

All new vs seven passes. Static only.

Shell-fixable:
1. Contacts has no "Text" action — ContactsWindow.qml:538-562 offers Call/Mail/Maps/QR; Messages accepts number prefill (MessagesWindow.qml:20-28); Phone.qml:48-51 exposes openMessages(). Sketch: add Text button.
2. Contacts' Call bypasses unified dial path — ContactsWindow.qml:62,545 uses xdg-open tel:; Modem.qml:36-42 has callNumber() preferring Link dial pad. Sketch: call Modem.callNumber(n).
3. Dial pad ignores address book — CallsWindow.qml:52-58 bare TextField; Link.contacts populated but never bound; GTK app has T9 suggestions. Sketch: expose calls_view.suggestions() via link.py contacts.
4. Call log no search/filter or delete/clear/undo — CallsWindow.qml:130-159 flat read-only; GTK app has per-day grouping, delete, clear, undo.
5. Recordings not tied to caller and cannot be replayed from log — CallRecorder.qml:16-25 timestamp-only filename.
6. Messages cannot start new thread or search — MessagesWindow.qml:38-46,141-164; link.py:185-248 no compose/search command.
7. Messages silently truncates bodies and loses group recipients — bridge/link.py:210 slices to 200 chars, :198 keeps addresses[0], :245 sends to single address. MMS/group threads appear one-to-one.
8. Text send cannot choose device or line — link.py:241 always _first_device(); dial can pick line.
9. Link device management KDE Connect-only — Phone.qml:20-32 kdeconnect-cli; Link.devices can be GSConnect/Bluetooth/landline but no pair/unpair/ping/clipboard UI.
10. Link engines exist but not surfaced — daemon exposes Bluetooth/USB/Wi-Fi tethering (service.py:331-342), clipboard sync (:374-376), phone camera as PipeWire webcam (screen_stream.py:640-650), remote shutter/volume/media (phone_remote.py:1-59), but link.py:42-45 imports only phone/calls_log/contacts/lines.
11. Modem: no PUK, USSD, call forwarding or VoLTE/VoWiFi readout — modem.py:43 knows sim-puk but handle() only SendPin; no Modem3gpp USSD/forwarding; report() never reads voice/EPS state.
12. Modem: no delivery reports or local SMS store — modem.py:131-139 only received; :160-165 emits sent immediately without watching Sms State; no on-disk store.
13. Gamescope console lacks several shell settings — shani-gamescope-control:870-936 has Network/Bluetooth/Audio/Display/Updates/Password/Reset/Performance but no Users/accounts, Firewall, VPN, Date & time, Locale or Accessibility tile.
14. Silent failures present as "no phone" — link.py:124-127,192-195,224-227 swallow every exception as []; MessagesWindow.qml:51 says "No phone is connected" even on bridge error.
Needs phone/hardware/server: 15. Multi-SIM selection (modem.py:77-84 always modems[0]); 16. Real group/MMS picture receive, delivery receipts, visual voicemail, spam blocking; 17. Find-my-device/remote locate (only ring() at link.py:281-291).

## File-format addendum (agent ses_dfbd91e06ffeLTNYXfM5zIXwP5 background grep)

Flatpak fallbacks confirmed present in shani-install-media/cache/flatpak_data/:
- Office: org.onlyoffice.desktopeditors shipped, .desktop covers DOCX/XLSX/PPTX/ODT/ODS/ODP plus RTF/HWP/EPUB/FB2/DjVu/OXPS/XPS/PDF. Makes office-format gap lower-risk; default already Flatpak covering more types than shell app. Shell's own path remains absent.
- Images: org.gnome.Loupe present, registers image/heic; confirms HEIC/raw/image fallback.
- PDF: org.gnome.Papers present (application/pdf=Papers in mimeinfo.cache).
- Feeds: com.vivaldi.Vivaldi registers application/rss+xml, partial RSS fallback (not OPML/tags).
- Also shipped: Gnote (x-scheme-handler/note), GNOME Maps (geo:/maps:/GPX/KML), Fragments, Warehouse.
One correction: OnlyOffice also claims EPUB/OXPS/DjVu/FB2, so office gap lower-risk than first appears. Authoritative skel file is shani-pkgbuilds/shani-desktop-niri/etc/skel/.config/mimeapps.list.

## Energy sustainability & hardware longevity (agent ses_dfbc71894ffefPJqxvd2iDuY1W)

Static only. Skip-list items (battery health/cycles, charge limit, power profiles, thermal sensors, per-app power, UPS, GPU/VRAM fit) not re-filed. [S]=shell-fixable, [K]=firmware/kernel/daemon.

Already present — do not re-file: health ring + cycle count (SettingsBattery.qml:76-124, battery.py:58,65), charge-limit Picks (SettingsPowerKeys.qml:166-172, shani-admin.py:275), PPD profile tile (SidebarTiles.qml:222-224), ambient-light servo (AmbientLight.qml:26-97), VRR + 60Hz-on-battery (SettingsDisplays.qml:196-200,324-326), OLED pixel-shift (ScreenSaver/Cover.qml:101-109), fan RPM/temps in Cassini, minimum requirements (shani-docs/docs/install/requirements.md:11-19).

1. [S] "Dim the screen" draws a black overlay; never lowers backlight. Idle/Dim.qml:22-27 55%-opacity Rectangle; on LCD backlight stays full. Sketch: on Idle.dimmed call Brightness.set(value*0.5) and restore on wake.
2. [S] No energy-consumption or CO2 readout. battery.py:69 instantaneous W shown only at SettingsBattery.qml:134; nothing accumulates Wh. Sketch: integrate W into "energy used today" with configurable gCO2 factor.
3. [S] No charge timer or battery-care schedule. Static cap only (SettingsPowerKeys.qml:166-172). Sketch: "charge to X% by <time>" picker applying threshold on systemd timer.
4. [S] Power mode bare three-way cycle with no effect explanation. Power.qml:175-180; tile/OSD print only label. Sketch: show PPD driver + one line "CPU governor / platform profile / brightness cap".
5. [S] Profiles don't coordinate screen/keyboard light. Power.qml:127,132,159,179 write only PowerProfiles.profile; Brightness.qml and KbdBacklight.qml have no Power reference. Sketch: on PowerSaver cap Brightness ~70% and force keyboard backlight off.
6. [S] Always-on polling keeps shell busy when idle. Agenda.qml:224 and Tasks.qml:89 every 10min, Housekeeping.qml:59 every 24h, Printing.qml:42 every 10min all running:true; NightLight.qml:48-59 every 60s, KbdBacklight.qml:102-107 every 30s. Sketch: gate on visibility.
7. [S] No way to end a stuck app wake-lock. Idle.qml:27-37 counts/names inhibitors, SidebarTiles.qml:214 shows name, no release action. Sketch: "End wake locks" action.
8. [S] Auto-brightness no calibration or battery ceiling. AmbientLight.qml:75-77 fixed lux curve, first IIO device, polls 5s. Sketch: calibrate button and battery-only cap.
9. [S] Battery age never shown. battery.py:59-77 has health/cycles/voltage/temp but no manufacture date; SettingsBattery.qml:235-243 shows tech/vendor/model.
10. [S] Refresh-rate reduction on battery is hard 60Hz step. DisplayModes.js:11-20 picks lowest mode >=59Hz. Sketch: idle-aware policy high Hz active/60Hz after dim.
11. [S] Component health split across three surfaces (SMART in Disks.qml:62-72, fan/temps in Cassini, battery in SettingsBattery.qml); no summary. Sketch: "Hardware health" card in Settings > About.
12. [S] No repairability documentation — grep finds "repair" only for btrfs/Flatpak/rollback. Sketch: docs/system/repair.md.
13. [S] No support lifecycle/EOL/LTS policy. shani-docs/docs/updates/channels.md:9-49 defines only latest/stable. Sketch: support-policy page surfaced in Settings > About.
14. [K] True timed charging needs EC support.
15. [K] Direct governor/EPP control — PPD owns it.
16. [K] Per-key RGB — no OpenRGB/hidapi bridge.
17. [K] True energy accounting — no powercap/RAPL reader.
18. [K] Backlight dim outside brightnessctl — DDC/CI fallback only.
Highest value × ease: #1, #2, #4, #5, #6, #13. Risk: nothing hardware-verified; #1 could double-dim where firmware dims on idle.

## Additional fix from this pass

- Switcher.qml open() now sets `grouped = buildGroups().length > 1` so Alt+Tab with a single app still cycles that app's windows instead of showing one dead tile (auto-disable grouping when there is nothing to group).

---

# Ninth pass — full reports

## Crash handling, diagnostics and self-recovery (agent ses_dfb9fb005ffeca9334i6SnhxBL)

Read both docs (2,657 lines) first. Skipped prior-pass topics (niri crash recovery, session lifecycle, audit trail, problem reports, logs panel, shani-doctor, health checks). Static analysis.

1. Mid-conversation bridge death spins forever. Services/Chronoa.qml:135-139 onConnectedChanged sets only state="offline"; busy/step/approval never cleared, no turn timeout. Island.qml:30,80,152 keys spinner off Chronoa.busy. Sketch: on disconnect clear busy/step, emit system("Chronoa stopped responding"), open panel; 60s turn watchdog.
2. Bridge never detects Chronoa D-Bus death. bridge/chronoa-bridge.py:389-412 subscribes to Agent.Event but no NameOwnerChanged watch, no turn timeout; turn_filter waits for done that never arrives. Sketch: watch AGENT_NAME owner loss, broadcast error event, per-turn timeout.
3. Persistent QML bridges die silently. Services/Plugged.qml:248-255, InputPlumber.qml:122-126, Modem.qml:46-50, Thunderbolt.qml:28-31 are running:true Processes with no onExited restart — Quickshell does not auto-restart. Only LauncherEntries.qml:39-41 retries (blindly), Files.qml:150-195 has a real watchdog. Sketch: one shared bridge wrapper with retry+backoff.
4. No watchdog for a hung shell. data/systemd/shani-shell.service:21-22 Restart=on-failure only; no WatchdogSec/sd_notify. Frozen event loop = dead desktop systemd never touches. Sketch: WatchdogSec=30 + QML keepalive.
5. Crash loop ends in failed unit with no UX. RestartSec=2 + default StartLimitBurst=5/10s trips after ~5 crashes; no StartLimitAction, no notice.
6. No user notification for any bridge restart. Bridge.qml:37-42 reconnects silently; LauncherEntries.qml:39-41 retries silently. Sketch: notify after 3 rapid restarts, name service, offer Retry/Report.
7. No failure counting/self-diagnosis. Zero NRestarts/RestartCount reads; health-check.py:43-97 has only space/failed-units/writable/tools. Sketch: systemctl show -p NRestarts.
8. Unsaved editor content lost on crash. TextDocs.qml:42-86 persists only open paths in text-editor-session.json; buffers memory-only. Sketch: autosave dirty buffers to XDG state every 30s.
9. No "desktop restarted" signal. Nothing records abnormal previous exit. Sketch: clean-shutdown marker, toast + diagnostics if absent.
10. No crash dumps. No coredump config; Quickshell segfault leaves no backtrace. Sketch: enable systemd-coredump.
11. Problem report lacks crash specifics. system-report.py:100-140 has journald errors and failed units but no per-bridge logs, restart counts, coredumps.
12. No automated or crash-triggered reporting. Report is manual button in SettingsAbout.qml:59-75.
13. Half-dead bridge invisible. Bridge implements ping (chronoa-bridge.py:206-207) but Bridge.qml never sends one. Sketch: 30s ping/pong.
14. Almost no diagnostic logging. Common/Log.qml:46 is tree's only console.log; Log.scoped appears only twice (Files.qml:27, Proc.qml:24). Silent catch(e){} at Bridge.qml:32, Plugged.qml:253, chronoa-bridge.py:395.
15. Unbounded dev logs/unconfigured journald. dev/session.sh:107,116-241 redirects every daemon to $L/*.log with no rotation; no journald.conf ships.
16. Socket unlink race on restart. chronoa-bridge.py:419-423 unconditionally unlinks socket; fast systemd restart with lingering old process can remove live socket.
Comparison: GNOME feeds crashes to ABRT/gnome-abrt; KDE DrKonqi shows backtrace dialog; Windows Reliability Monitor timeline; macOS Crash Reporter .ips. Shani has restart-on-failure, manual text report, none of dialog/timeline/backtrace/consented sending.

## Multi-monitor and display hotplug edge cases (agent ses_dfb9f8624ffeD6FLTgTL3R5qRi)

Skipped listed items (per-monitor wallpaper/scale, EDID, hotplug workspace restore, arrangement profiles, named targets, swap-monitors, fractional scaling) and Ruler/Magnifier multi-monitor already in GAPS.

1. [S] Window previews use logical geometry for physical-pixel capture. WindowPreview.qml:27-34 derives grim -g rect from Displays.outputs x/y/width/height (logical pixels, Displays.qml:241-243) but grim expects physical. On 1x+2x rect is half-size/wrong origin. Dock.qml:530 passes Niri.focusedOutput not window's own output. Sketch: multiply by output scale, pass window's output.
2. [S] Ruler pixel ratio from arbitrary monitor. Ruler.qml:37-41 sets ratio once from Displays.outputs[0].scale (sorted by connector); grim captures composite of all outputs, RulerPanel fits into focused screen. Mixed scale/portrait+landscape wrong. Sketch: grim -o <focusedOutput>, ratio from same output.
3. [S] Monitor greeted while locked never greeted after unlock. Plugged.qml:72 drops greetings when Lock.locked before marking seen; onArrived fires once, Displays.known contains output, no replay. Sketch: queue arrivals while locked, flush on unlock.
4. [S] Presenting survives unplugging its source. Plugged.qml:164-171 only ends presentation when target output departs; unplugging mirrored-from monitor leaves dead wl-mirror source, DND/caffeine on.
5. [S] Focus-following single surfaces teleport between monitors. ~30 surfaces bind screen: find(name===Niri.focusedOutput)||screens[0] (Island.qml:26, Osd.qml:213, Launcher.qml:32, WindowMenu.qml:18, shell.qml:203). Approval card/launcher/control centre on monitor A jumps to B on focus change; unplugged focused output falls back to screens[0]. Sketch: sticky output per open surface.
6. [S] Lid close produces no shell behaviour. InputConfig.qml:137-138 forwards lid events; TabletMode.qml:27-28 sets lidClosed, read only by state dump. With HandleLidSwitchExternalPower=ignore, closing lid on external monitor leaves internal panel on. Sketch: on lid-close with external outputs, turn off internal, focus external, re-arm idle.
7. [S] "minimised" is one global workspace name across all outputs. Niri.qml:92-94 finds first workspace named minimised; minimise() moves windows there by name. With 2+ outputs minimising on non-first monitor moves windows to other monitor's hidden workspace. Sketch: per-output hidden workspace minimised:<output>.
8. [S] "Extend" assumes landscape right-hand neighbour. Plugged.qml:180-181 sets x=max(right edge), y=0 unconditionally; portrait beside landscape top-aligned not centred; no left/above choice.
9. [S] Dock layout swaps behind lock, only two states. Docking.qml:25-29,41 follows hotplug with no Lock.locked guard; 3+ monitors collapse to "docked". Sketch: defer follow() until unlock; key layout by output-set.
10. [S] Per-monitor wallpaper dropped on lock/overview. LockScreen.qml:205 and Wallpaper.qml:38 use global Theme.wallpaper; live background honours wallpapersByMonitor. Sketch: use same wanted resolver with surface output name.
11. [S] Magnifier shows stale frame after focus moves. Magnifier.qml:18 rebinds screen to focused output but grab() only on open/right-click. Sketch: onScreenChanged: grab().
12. [S] Quickshell.screens and Displays.outputs desync during hotplug. Per-output layers built from Quickshell.screens (Bar.qml:21, Wallpaper.qml:20) but geometry from Displays.outputs (Bar.qml:211-212,296) which lags rescan. New output briefly gets width-0 bar. Sketch: guard geometry bindings.
N1-N4 niri/portal-level: mirror is fullscreen wl-mirror not cloned output; no audio routing for presentation; idle screen-off all-or-nothing; per-output refresh/VRR/scale config-only with polling.
Risk: S1/S2 need real 1x+2x setup; if niri reports physical pixels in tile_pos_in_workspace_view only the origin term is wrong.

## Network protocol depth (agent ses_dfb9f5aeaffeAXXJHr27cq9Ho1)

Shell-fixable:
S1. SMTP uses implicit TLS on STARTTLS port 587. mail.py:631 defaults port 587, :645-648 defaults ssl:true → SMTP_SSL (465-style) on submission port. [FIXED this pass: derive TLS from port]
S2. STARTTLS optional → credentials in clear. mail.py:653-661 logins even without STARTTLS; :381-386 opens plain IMAP4 and LOGINs with no STARTTLS. [FIXED this pass: refuse cleartext to remote hosts]
S3. UID/sequence mix makes search results unclickable. imap_search:462,466 returns UIDs via box.uid(), but imap_read:493, imap_flag:524, imap_move:538, imap_delete:605, imap_source:553, imap_attachment_data:567 treat ID as sequence via box.fetch/store. Acting on a hit can flag wrong message. Sketch: use box.uid() everywhere.
S4. Feeds never send conditional GET. feeds.py:140-149 no If-None-Match/If-Modified-Since; refresh_one:254-260 stores no ETag/Last-Modified, so every refresh re-downloads full bodies.
S5. No OAuth2/XOAUTH2 anywhere. password():81-96 only plaintext; Google/Microsoft/modern iCloud need app passwords.
S6. No DKIM/SPF/DMARC shown. imap_read:503-512 and mh_read:321-330 discard Authentication-Results/Received-SPF.
S7. RSS content:encoded and full Atom content lost. parse_feed:180-186 never checks http://purl.org/rss/1.0/modules/content/.
S8. No S/MIME or PGP handling. bodies_of:164-179 only text/plain and text/html; signed/encrypted parts ignored.
S9. Folder LIST parsing assumes / delimiter and unescaped names. imap_folders:397 splits on literal ' "/" '.
S10. Full-message refetch on every list; no cache/UIDVALIDITY/CONDSTORE. imap_list:425 BODY.PEEK[] last 100 messages per folder each open.
S11. No attendee RSVP roundtrip. events:151-152 hardcodes organizer=""; _ical_text emits REQUEST/ATTENDEE but nothing reads PARTSTAT/RSVP or emits iTIP REPLY; edits never bump SEQUENCE.
S12. Webcal subscriptions unsupported. account_add:551-598 only http(s) WebDAV.
S13. SFTP host-key trust-on-first-use. connect_sshfs:1402-1427 uses StrictHostKeyChecking=accept-new (MITM on first connect), no identity-file picker.
S14. Proxy bypass list hardcoded. Proxy.qml:24 no_proxy=localhost,127.0.0.1,::1; no user-editable list.
S15. Radio stations from directory played without scheme validation/metadata. Radio.qml:95,119.
Needs server/daemon: D1 OAuth2 token acquisition/refresh; D2 CalDAV sync conflict resolution; D3 Files network protocol depth (nfs:// accepted though gvfs has no backend, no SMB dialect); D4 rclone backend config/encryption; D5 per-app proxy.

## Audio routing and PipeWire graph depth (agent ses_dfb9f305affev15wH3aLLU6GxU)

Corrections (brief was stale — do NOT re-file): 10-band EQ, bass boost, compressor, loudness (EBU R128), stereo width/mono, crossfeed, spatialiser, AutoEq, impulse response ALL BUILT (SettingsSound.qml:105-263, SoundFx.qml:83-160). Device switching on plug-in/BT-connect delegated to WirePlumber and OSD-reported (Audio.qml:137-161). Per-app volume mixer AND per-app output routing helper exist (SidebarSliders.qml:73-93, Audio.moveStream() via pw-metadata target.object Audio.qml:95-103). RNNoise mic suppression (SoundFx.qml:232-291). Wake word/TTS voice still noted only.

Shell-fixable:
1. Per-app output picker absent from mixer (moveStream exists but app rows only volume/mute). Sketch: sink dropdown per app row.
2. Echo cancellation is detection-only. echo_cancel_active() never enables (shani_link/audio.py:66-81). Sketch: mirror RNNoise filter-chain pattern.
3. No separate mic monitoring level. Mic slider capture gain only.
4. Lock-screen media controls shallow — prev/play/next and art only (LockScreen.qml:416-445); sidebar has switching+seek. Sketch: reuse sidebar card.
5. Media keys follow sticky preferred player. Media.current = preferred||playing||first (Media.qml:13-15).
6. No limiter/true-peak ceiling. 150% over-amplification distorts; only compressor.
7. No notification/media ducking. No duck reference.
8. Recording no latency compensation or live monitoring.
9. Channel remap/swap not exposed; only L/R balance.
10. Album-art fallback missing — raw trackArtUrl, blank tile for empty/embedded art.
11. Wake word is a label, not a control.
PipeWire/daemon-level: 12 A2DP↔HFP auto-switch (needs WirePlumber Lua policy); 13 beamforming (hardware-specific); 14 virtual sink/source/device-combining UI; 15 graph viewer/patching; 16 per-app recording; 17 TTS voice selection.
Highest value × ease: #1, #2, #3, #4.

## Developer tooling experience (agent ses_dfb9f07fcffecUNq9sFDtvq07u)

Hot reload: 1. No QML reload — dev/session.sh:241 starts qs once; dev/render.sh:124-132 pkill + re-source. Only settings data reloads (Settings.qml:1-4). Sketch: dev-only reloadUi IPC.
Debugging: 2. No IPC tracer — 519 functions (shell.qml:258) none logs invocation. 3. Log.qml effectively unused — SHANI_LOG filtering exists but Log.scoped appears only twice; console.log/warn total 4. 4. No in-shell view of shell diagnostics — LogsPanel reads journalctl not qs.log; QML output to out/logs/qs.log only readable by leaving GUI. 5. No programmatic IPC discovery beyond fixed state() blob; no listIpc/help/describe.
Scaffold: 6. No scaffold command for new app/module/service/bridge (only tools/i18n.py). 7. Adding one IPC call means three manual edits (shell.qml, bin/shani GROUPS + _register, test). 8. Shell "app" has no single registry (APPS dict + Ui bool + IpcHandler + state line + launcher modules).
API docs: 9. ~60 Common + ~60 Services files have no contract docs beyond prose layout list. 10. Bridge contracts only per-file docstrings; no aggregate, no version marker in ~70 bridges.
Testing: 11. No QML unit-test harness — tests pytest only; no qmltestrunner/TestCase/SignalSpy. 12. No per-component test template. 13. Dev loop container-only — no documented host-native path.
Packaging: 14. Dev install only symlinks QML; bridges installed by PKGBUILD, no dev install of modified bridges. 15. PKGBUILD pinned to git commit — no local-checkout build. 16. No checklist of files a feature must touch.
Versioning: 17. No API version for IPC or bridges — no SHANI_IPC_VERSION, bridge --version, deprecation field.

## Config migration and versioning (agent ses_dfb9ede4bffewuDDlzHg3c9EJw)

1. No schema version in any state file — only release-notification marker (WhatsNew.qml:20-34). Settings.qml:1-6, feeds.py:45-77, mail.py:44-56, music-library.py:124-130 bare dicts.
2. Existing users never receive changed defaults — "created on first change" misleading; writeAdapter() writes all ~300 keys at once (dev/shell-test.sh:266-267); applyOutside prefers file value over defaults[k], so changed defaults invisible to anyone who toggled anything. Sketch: touched[] set, re-apply new defaults to untouched keys on schema bump.
3. Renamed/removed keys neither migrated nor cleaned — only one-off dockAutoHide→dockVisibility (Settings.qml:98-100); resetAll loops defaults only, stale keys survive.
4. Corrupted settings.json only file with safety net (copies to .unreadable-ts + notify). ~14 other QML sites and 4 bridges silently reset: ScreenTime, Launcher, Shelf, PlayQueue, Clipboard, Notifs, Reopen, Weather, VoiceRecorder, TextDocs, Updates, Tr, feeds.py, mail.py, music-library.py, PhotosWindow.qml.
5. Most state files written non-atomically — only Settings.qml:137, Updates.qml:33, Notifs.qml:208 set atomicWrites:true. Others plain writes; crash mid-write → permanent loss.
6. Corrupt feeds.json/mail.json destroy subscriptions/account config irrecoverably.
7. No downgrade migration across blue-green rollback — /home separate subvolume outlives both slots; settings written by new version read verbatim by old.
8. Pre-deploy home snapshots not version-labelled, only two kept (shani-backup/home.py:131,229-244).
9. Factory reset preserves all per-user shell config/state (shani-reset.sh:21-27).
10. Dev session doesn't isolate bridge state — bridges derive paths from HOME, XDG_STATE_HOME unset; tests write real /root/.config.
11. No settings import from GNOME/KDE/COSMIC editions.
12. Wrong-but-valid JSON passes silently (.get on any type, Object.values on any type).
13. No migration tests exist.
14. State lives in four roots with four corruption stories.
15. Two different version files — /etc/shani-version vs /etc/shani/version (shani-deploy.sh:1547 vs shani-upgrade-adviser.sh:44-49).
Risk: pre-deploy snapshots cover only two updates, so a third makes older configs unrecoverable.

## External-app interoperability (agent ses_dfb9eb030ffe3MXcIwtwWCXisT)

Skipped parent's list and items already filed (mailto/geo handlers, share-into-apps, plain-text copy path now text/uri-list at Files.qml:922, grouped notifs, urgency-2 DND bypass, FileChooser-only portal, window thumbnails).

Shell-fixable:
1. Per-app rules cannot target a named workspace — SettingsWindows.qml:186 hardcodes ["","1".."5"], writer emits any name (WindowRules.qml:49).
2. Window-rule UI covers ~6 of niri's ~25 properties — WindowRules.qml:40-55 emits mode/workspace/output/size only; border, focus-ring, opacity, background-effect, geometry-corner-radius, block-out-from, dynamic is-focused missing.
3. No "screenshot this window" for external app — Screenshots.qml:112 only screenshot-screen; WindowMenu has no capture action.
4. Inbound drag accepts file URIs only — FileDropArea.qml:14 keys ["text/uri-list"], DropZone.qml:86-89 hasUrls only. X11 apps offer UTF8_STRING/text/plain, GTK/GIMP/Firefox offer image/png; no target accepts either.
5. DropZone trusts any URL scheme — forwards http:// drags as bogus local paths.
6. Mail is a dead row in Default Apps — SettingsDefaultApps.qml:23 queries mailto but no installed entry declares it (bin/shani:528 mail mimes []).
7. No scheme handlers on desktop entries — bin/shani:598-606 writes only MimeType; skel registers magnet/dht/tel/ftp to third parties but nothing for mailto/geo/message/rfc822/web+*.
8. Minimise/restore forgets original workspace — Niri.qml:117-122 restores to currently focused workspace; external app comes back on wrong workspace after Show Desktop.
9. Flatpak portal notifications bypass rule engine — no org.freedesktop.portal.Notification reference; niri-portals.conf delegates Notification=gtk; NotifsRules.qml matches appName/summary/body only.
10. Snoozed notifications lose identity and actions — Notifs.qml:143-163 re-posts with notify-send dropping desktopEntry hint and all actions.
11. X11 PRIMARY selection unsynced — config.kdl:100 wl-clip-persist --clipboard regular only, no --primary.
12. XWayland input-method env incomplete — config.kdl:84-94 sets XMODIFIERS/QT_IM_MODULE but no GTK_IM_MODULE; fcitx5-gtk ships.
13. Share sheet shells out instead of portal Mail/Share — Share.qml:32 xdg-email, bridge/portal.py only FileChooser.
N14-N16 niri/portal-level: sharing one window exposes whole monitor (portal-wlr captures outputs only); no compositor session manager; XWayland per-app scaling compositor-owned.
Risk: niri action names and screenshot-window availability not verified against installed binary.

## Fixes applied this pass

- Duplicate desktop ID: ShellApps.js "Password Generator" pointed to dev.shani.Passwords (same as Passwords and Keys) — corrected to dev.shani.PasswordGenerator; tests/test_app_registry.py (523 checks) caught it.
- SMTP STARTTLS bug and IMAP cleartext login in bridge/mail.py corrected (security).
- Two new agent test files added: tests/test_app_registry.py, tests/test_cli_ipc.py (608 checks).

---

# Tenth pass — full reports

## Advanced text editor features (agent ses_dfb935d11ffeQshGadkNuvJvm5)

Correction: editor well ahead of docs — session restore, multi-caret, snippets, TextMate theme chooser, bookmarks, go-to-line, current-line/matching-brace highlight, word count, regex find all exist. Frontier is code intelligence and project/IDE workflow.

Feasible in QML/small bridge:
1. Jump to matching bracket — matchBrace() implemented (TextEditorPanel.qml:371-391) used only to draw a box (:674-684); no key moves cursor there. Sketch: Ctrl+] in shortcut().
2. Auto-save to disk — setText() memory-only (TextDocs.qml:199-215), save() manual, no autoSave setting. Sketch: Timer in TextDocs after N seconds inactivity.
3. Unsaved-buffer recovery across restart — saveSession() writes only {paths,active} (TextDocs.qml:79-83); unsaved text lost despite header comment. Sketch: include text/eol/modified in session JSON + Recover.
4. EOL selector — detected and preserved (TextDocs.qml:189) but user cannot choose LF/CRLF. Sketch: status-bar chip.
5. Type-over closing bracket — handleAutoclose() (TextEditorPanel.qml:89-124) but typing ) next to auto-inserted ) yields )). Sketch: advance cursor if next char equals closeOf(c).
6. Soft-wrap modes — one boolean (TextEditorPanel.qml:46,720). Sketch: off/wrap-viewport/wrap-column + column ruler.
7. External-change/conflict detection — probed only at open (TextDocs.qml:142-145), no watcher/mtime check; second editor can overwrite silently. Sketch: DirMonitor/periodic stat + Reload/Discard banner.
8. Breadcrumbs (cursor path) — status bar path + line/column only. Sketch: regex-scan braces/function|class|def above cursor.
9. Format document — panel spawns no process. Sketch: bridge dispatching black/rustfmt/prettier/clang-format by win.lang.
10. Git status/diff for open file — git exists but editor never calls it. Sketch: side pane with git diff rendered through diff highlighter.
11. Open folder → file tree → project search — TextDocs.open() refuses directories (TextDocs.qml:143,169); find/replace per-document. Sketch: left panel reusing Files listing + grep -rn bridge.
12. Code folding — gutter only line numbers and bookmark dots. Sketch: compute indent/brace ranges, elide in both overlay TextEdits.
13. Selection grow/shrink — Alt+Shift+Down adds vertical cursors but no structural expand-to-word/string/block.
14. Sticky scroll — no pinned enclosing scope header.
15. Encoding selector — probe rejects NUL-bearing via grep -qI (TextDocs.qml:143), so UTF-16/32 "Not a text file". Sketch: BOM sniff + explicit codec.
16. Minimap — low value per effort.
17. TextMate grammar data — 0 .tmLanguage/.tmTheme ship; all files fall back to keyword regex. Overlaps earlier file-format finding.
Needs LSP daemon: 18 LSP client core; 19 completion/IntelliSense; 20 diagnostics/problems; 21 go-to-definition/find references; 22 rename symbol across files; 23 hover docs/signature help; 24 embedded terminal/build tasks; 25 collaboration/CRDT (out of scope).
Top five by value × ease: #1,#2,#3,#4,#5.

## Advanced notes features (agent ses_dfb9333d7ffetpC8YMY23tOnRf)

Feasible in QML:
1. Diff/compare before restore — history copies exist but restoreVersion() overwrites immediately (QuickNotes.qml:528-563). Sketch: Process diff -u in read-only pane.
2. Note templates on create — create() writes empty file (:245-259). Sketch: ~/Documents/Notes/.templates/<notebook>.md with {{title}}/{{date}}.
3. Daily/periodic notes — no date-based creation. Sketch: Today button.
4. Outgoing-link index + orphan detection — links() regex only on current note (:440-449). Sketch: global pass mapping id → [[targets]].
5. Tag index/tag graph/nested tags — tags() scans only root.text with #[A-Za-z0-9_-]+ (:567-574), no / and no cross-note co-occurrence.
6. Search operators (tag:, path:, created:) — search() name/current-body substring (:462-469), searchBodies() grep -liF (:477).
7. Regex toggle + saved searches — only -F; no saved searches.
8. Pin/favorite + colour coding — note model {name,path,notebook,id,mtime} only (:90).
9. Nested notebooks — validNotebook()→valid() replaces / with space (:241-244), list globs one level (:80).
10. Templater-like variables beyond creation.
11. Kanban/table view — one ListView with one delegate.
Needs backend: 12 HTML export with real Markdown + CSS (htmlDocument escapes into <pre> :393-397; markdown_lite.py exists in sibling package); 13 styled PDF export; 14 static-site/multi-note publish; 15 block references/transclusion; 16 YAML front matter; 17 sync conflict resolution; 18 plugin/extension API.
Top value × ease: #1–#5, then #6/#8. Risk: #9/#16 need atomic writes — Notes uses execDetached shell writes (:256,314,334).

## Advanced files features (agent ses_dfb9307a8ffe2BOEYZ87vcvec2)

Already built not re-filed: boolean star + starred: place, Ctrl+L path box, Recent sidebar, per-tab bar, read-only Properties perms, checksums, folder compare + dry-run sync confirm, zip append via zipadd.py, dup detection via dupes.py.

1. No per-file Previous Versions / restore from btrfs snapshots — daily home snapshots exist (Backup.qml:2-5,18-21) but per-file restore only hands off to external GUI (:33-43); Files context menu has no version action. Sketch: files.py versions <path> + context action.
2. Search no operators or regex — search() only w in name.lower() (files.py:1481-1506), content search rg -F fixed (:1531-1543), searchPath concatenates words (Files.qml:1326-1329).
3. Batch rename numbering-only — batch_rename() only substitutes # (files.py:1611-1639). Sketch: s/pattern/repl/ + date/camera tokens.
4. Bulk permissions not exposed; no owner/ACL/xattr/immutable — chmod-pairs accepts many (files.py:821-835) but Properties one path; no setfacl/setfattr/chown/chattr anywhere.
5. Folder sync one-way with no exclusions/conflict policy — _rsyncArgs only -a --delete/-au (Files.qml:1269-1272).
6. Archives not navigable as folders — Files only "Extract here"; Archive.qml lists in separate window. Sketch: archive:// VFS.
7. Stars one bit, not metadata — flat newline file of paths (files.py:773-803). No colors/tags/ratings/comments.
8. Search silently caps results — 300 hits/4s with truncated flag (files.py:1483-1506) UI never surfaces.
9. No saved searches.
10. Bookmark aliases cannot be written — parses label after URI (:1651-1669) but bookmark() appends bare URI (:1672-1685).
11. Per-tab history actually global — one history/historyIndex (Files.qml:33-34); switchTab calls open() which pushes same stack.
12. No content search inside archives.
13. No compare of two archives.
14. No bulk resize/convert from Files.
15. No extract-to-multiple-destinations.
16. Exif/date tokens absent from rename and search — props() reports no EXIF though PhotoMeta exists.

## Advanced calendar features (agent ses_dfb92de52ffe2hwnOUgk6Tlerd)

Tier A:
1. Editing any recurring event destroys custom RRULE — ruleFromForm() reconstructs FREQ+UNTIL only (CalendarPanel.qml:249-255), openEditor feeds e.rrule (:275), saveEditor writes back (:430). Imported FREQ=WEEKLY;BYDAY=MO,WE,FR becomes plain FREQ=WEEKLY after any edit. DATA-LOSS BUG. [FIXED this pass: carry original rule when repeat controls untouched]
2. No custom recurrence patterns — five fixed chips, end date only. No INTERVAL/BYDAY/nth weekday/BYMONTHDAY/COUNT though agenda.py:_safe_rrule accepts them.
3. No recurrence preview.
4. No agenda-list/multi-day schedule view — views only Month/Week/Day/Year.
5. Control-centre mini-month shows no events — zero Agenda references. Sketch: bind hasEvent() helper.
6. Event location inert text — no Maps link/geo URI/travel estimate.
7. No calendar export of a date range — agenda.py commands add/edit/delete/import/accounts/calendars only, no export.
8. No calendar groups/merge — flat show/hide chips only.
9. Recurring tasks a 3-value sidecar — Tasks.qml:15-16,43-49 uid → daily|weekly|monthly, no interval/weekday/count/end.
10. No tasks↔calendar integration — TasksWindow has no Agenda/Calendar reference.
Tier B:
11. No per-occurrence edit/delete (series exceptions) — events() gives every occurrence master UID (agenda.py:150,162), edit/delete get_object_sync(uid) on master; no RECURRENCE-ID/EXDATE.
12. No free/busy or find-a-time — never calls ECal get_free_busy_sync.
13. No busy/tentative/out-of-office status — events() fixed field set (:140-157).
14. No working hours — week grid all 24h; ScreenTime.qml:92 has unrelated hardcoded 09–17.
15. No time blocking/Focus–calendar coupling.
16. No subtasks — flat row list, tasks.py no parent field.
17. No publish-a-link/delegate access.
18. No travel-time buffer.
19. No unified reminder list.

## Advanced email composition (agent ses_dfb92b320ffekOybWqgLs0cefW)

Verdict: Mail is a four-pane reader with single plain-text compose box. All new at this depth.
Composition: 1 recipient autocomplete from Contacts (To/Cc/Bcc bare TextFields MailWindow.qml:353-355, Contacts.qml:16 holds contacts) — cheapest high-value; 2 per-account signature; 3 request read receipt; 4 delivery priority; 5 Reply-To override; 6 send later/schedule; 7 HTML/rich-text compose; 8 spellcheck in compose.
Attachments outbound: 9 drag files into compose (no DropArea); 10 attachment preview/open; 11 inline/CID images (mail.py:155 replaces <img> with [image]); 12 large-file handling/attach-as-link.
Organization: 13 message filters/rules on arrival; 14 quick filters (unread-only); 15 saved searches; 16 snooze until; 17 tags with colors/pin.
Conversation: 18 quote collapsing + load older (flattens quote into one > block; imap_list last 100 hardcoded :438).
Contacts/calendar: 19 add sender to Contacts/contact photos; 20 RSVP buttons in message (imap_read ignores text/calendar parts); 21 convert email to event.
Send lifecycle/keyboard: 22 undo send/outbox/failed-send retry; 23 draft autosave across restarts; 24 full keyboard navigation + compose-in-new-window.

## Advanced photo/video/media features (agent ses_dfb928217ffeTyGfz85t0hA50t)

Key finding: bridge/face.py:2 is face sign-in (linux-hello), NOT photo face detection; imgedit.py/convert.py only edit/transcode engines.
Feasible: 1 EXIF editor + IPTC/XMP (PhotoMeta.qml:57 exiv2 read-only, no -M set); 2 video subtitle embedding on export (convert.py:319-329 only metadata; sidecar SRT read in MediaPlayer but never burned); 3 perceptual duplicate photos (dupes.py byte-identical only); 4 video transitions on multi-segment join (concat = hard cuts); 5 photo tone controls (imgedit.py:83-100 only flip/rotate/crop/resize/marks); 6 video colour correction + text overlays; 7 speed ramping; 8 before/after compare (save destructive imgedit.py:103-123); 9 non-destructive edits/sidecar; 10 slideshow music/transitions/interval (fixed 3500ms Timer); 11 filters/presets; 12 geotag/map view (PhotoMeta reads no GPS); 13 smart/auto albums + memories; 14 scrobbling (PlayQueue.qml:246-264 only MPRIS); 15 related/recommendations (local metadata-only); 16 bulk metadata edit; 17 audio track mixing on export; 18 N-up print layouts/photo books; 19 social share targets.
Needs AI/model/hardware: face detection/naming; scene/object recognition; content-based recommendations; true multi-window PiP (compositor).

## Shell-specific utility surfaces (agent ses_dfb925707ffe1pGpBpRJJz0SC5)

Tour: 1 Skip indistinguishable from completion — Skip calls same finish() that marks tour seen (Tour.qml:130,39-43); no step persisted.
Quick Look: 2 no zoom/pan for images, no PDF page navigation (Image fixed PreserveAspectFit :100-109, PDF hardcodes -f 1 -l 1 :122); 3 no seek on previews; 4 no Share or Copy action.
Pinned capture: 5 BUG double-click opens image 2–3× — single-click handler xdg-open (:86) and onDoubleClicked again (:89), Qt fires clicked for both clicks. [FIXED this pass: removed onDoubleClicked]; 6 only one pin, no zoom (Screenshots.qml:17-22 single pinnedPath).
Screen saver: 7 never runs over lock screen (active requires !Lock.locked ScreenSaver.qml:18); 8 photo mode no curation/controls (Math.random with replacement :65-70).
Ambient light: 9 no-sensor mode silently overwrites brightness with clock curve (apply() uses timeLevel() :82,90-97); 10 sensor hotplug never detected (probe once at startup).
Tablet mode: 11 lid state effectively dead (TabletMode.qml:27-28 lidClosed only in state dump), tablet mode changes only OSK.
Shelf: 12 parked entries never validated (deleted files stay with broken thumbnails); 13 recents hardcoded (3 fixed dirs, 7 days, 12 items :38-41).
Housekeeping: 14 SMART warning re-notifies every 24h forever with no suppress/snooze/self-test (:53-55).
Smart: 15 no global opt-out and no privacy boundary — watcher always on, no Settings key, ships copied error text to Chronoa (:30-31,61-63). [FIXED this pass: added smartSuggestions setting gating running:]; 16 tiny vocabulary (no date→calendar, address→maps, file path→open, IP/tracking).
Smart replies: 17 maps grow unbounded and chips fixed (asked/suggestions never pruned :14-15).
Writing tools: 18 Replace fragile and destroys clipboard (no save/restore, fixed sleeps :97-105); 19 no custom instruction or before/after diff.
Ring: 20 hardcoded contents contradict "things you do most" claim (Tour.qml:35), Apps slice first 8 dock pins (:79); 21 keyboard/a11y thin (number keys only, no Accessible names on slices).
Bugs/dead code: PinCapture triple-open (#5), TabletMode.lidClosed unused (#11), SmartReplies maps never pruned (#17).

## Fixes applied this pass

- Calendar recurring-event RRULE loss: ruleFromForm() now returns the original rule verbatim when the person hasn't touched the repeat controls (repeatTouched flag).
- PinCapture double-click triple-open: removed onDoubleClicked handler.
- Smart clipboard watcher privacy opt-out: new Settings.data.smartSuggestions gate on Process.running.

---

# Eleventh pass — full reports

## Notification actions & quick-response depth (agent ses_dfb8c0de9ffeHDClcT6FL3PCo2)

Scope: static; skipped parent's listed items. Note GAPS.md:801/805 stale — Popups.qml:46-189 and NotificationCard.qml:395-410 now implement grouped stacks + progress bars.

1. Inline reply is a single-line TextField — no multiline/Shift+Enter, attachments, emoji/OSK, voice dictation, draft persistence; typed text dropped on expiry (NotificationCard.qml:304-315).
2. Action labels not localized — card renders a.text verbatim; shani-link posts hardcoded English "answer"/"Answer"/"Call back"/"Message" (NotificationCard.qml:55,330; incoming_call.py:279-280; missed_call.py:69-71).
3. Custom rule "actions" dead code — evaluate() returns arbitrary action strings but onNotification only branches on "block"; mute/hide/silence collapse to hide (NotifsRules.qml:73-77; Notifs.qml:243-247,256).
4. No "mark all read" semantic — clearAll dismisses everything; no read/unread flag; dock badge raw count (Notifs.qml:27-43,179-184).
5. Call actions Answer/Decline only — no quick SMS presets, send location, silence, add-to-contacts; missed calls only Call back/Message.
6. No action overflow — every action one Repeater in RowLayout with ElideRight; 5 actions squeeze unreadably (NotificationCard.qml:320-391).
7. Action icons advertised but never drawn — server declares actionIconsSupported but pill model only {text,run}.
8. Suggested replies send with one tap, no confirm/edit — LLM suggestion dispatched straight to sendInlineReply (→ paired phone via MAP) with no review/undo (NotificationCard.qml:293-300; SmartReplies.qml:29-34).
9. Snooze one fixed-length chip — no later today/tomorrow/next week presets or reminder integration (tomorrowMorning used only for DND).
10. Post-reboot "Earlier" entries inert — snapshot() drops desktopEntry and actions (Notifs.qml:192-198).
11. No one-tap "silence this conversation" — app-level silencing buried in overflow, per-app not per-thread.
12. Notification-centre groups never collapse — sidebar groups always expanded, Clear dismisses whole group with no undo.
13. No action-result feedback — card calls done() immediately after run(); failures logged only.
14. Test IPC invokes actions without context — notificationAct() calls a.invoke() with no args vs real clicks passing {notificationId,appName} (shell.qml:959-963).
15. "Ask Chronoa" has no consent gate — ships full summary+body to assistant with no confirmation.
16. Dock badge long-press shows launcher actions, not pending notifications (Dock.qml:566).
17. Reply-target state daemon-memory-only — map_notify.replies/incoming_call.shown lost on restart.
Highest value × ease: #1,#2,#4,#5,#8.

## Visual polish & micro-interactions depth (agent ses_dfb8bae64ffeYfVWF5vXBuDAOa)

Skipped documented items (reduceMotion, accent, matugen, bar opacity, glass, Theme.faint, focus ring, fontScale, niri Pop spring, NotificationCard:408 animation, edge swipes, empty-state actions).

1. Quick Panel no entrance or exit — QuickPanel.qml:18 flips visible, card has no Behavior; blinks. Sketch: Behavior on x/opacity mirroring Sidebar.
2. Quick-settings tiles hover but no pressed state — ControlCenter/Tile.qml:60 colour from containsMouse only; no pressed/ripple.
3. Toggle switches no press feedback/haptic tick — SwitchRow.qml:55-75 fixed bezier, onClicked only.
4. Haptics entirely absent — grep haptic|rumble|vibrate zero; only force-feedback diagnostic in Plugged.qml. Long-press silent.
5. Interaction sounds absent — SystemSounds.qml only volume/screenshot/charger/drive; no toggle/open/close/long-press/dismiss.
6. Notification swipe-back snaps — NotificationCard.qml:98-114 no Behavior on slide.x; failed dismiss jumps.
7. Dock icons can't be drag-reordered — movePin exists (Dock.qml:160-175) only context menu callers; control-centre tiles do drag-reorder.
8. Motion language fragmented — Theme.emphasized used in only 5 files; 7 easing types, ~24 distinct Theme.mot values 60ms–90000ms.
9. Surfaces don't appear from where you tapped — Launcher fixed y:28; no shared-element pattern.
10. Panel opening state-driven not finger-driven — Sidebar tracks finger only for dismissal; no drag-from-edge-to-open, no velocity carry-over.
11. No pull-to-refresh in any list — Feeds toolbar button/timer only.
12. Empty/loading/error swap instantly, no shimmer — no skeleton, Spinner only in Button.qml:78 and VoiceRecorderPanel.qml:356.
13. No in-app swipe-to-back — four edge gestures + long-press/pinch on 3 viewers; none of ~45 AppWindows has back-swipe.
14. Ripples on only two controls — Button.qml and IconButton.qml; ListRow/SegmentedTabs/SwitchRow/NotificationCard none.
15. 90-second ambient animation while cover shown — ScreenSaver/Cover.qml:51-52 breathing Theme.mot(90000).
16. Overlay stacking implicit — 30+ surfaces declare WlrLayer.Overlay with no cross-surface z; Ui.closeAll lists 12 flags.

## Backup/restore edge cases (agent ses_dfb8b598fffeH1jegSuhvVFEcM)

Verification:
1. No restic check anywhere — integrity inferred from single-file restore (restic.py:194-273); docs tell users to run restic check by hand.
2. Restore-test failure never fails backup — cli.py:217-220 exits on result.ok alone, merely prints test result.
3. Partial backup reported as success — restic.py:146-149 treats exit 3 (some files unreadable) as OK; files_error parsed away.
4. Restore test false negatives — restic.py:247-250 only files 0<size≤50MB; empty-file or single-large-file backups report no test file.
Restore correctness:
5. No space preflight, no cleanup after failed restore — restic.py:183-191 timeout=None, no df check; partial tree left on ENOSPC.
6. Full restores never verify — only restore_test passes --verify; GUI restore doesn't.
7. Local snapshot restores lose fidelity — home_page.py:79-86 shutil.copy2/copytree: no xattrs, no hardlinks, sparse fully allocated, FIFOs error.
8. No post-restore verification of local copies — only OSError caught.
Exclusions: 9 defaults leave Downloads and mounted filesystems (no --one-file-system, restic.py:42-47); 10 no user paths or pattern syntax.
Encryption: 11 no key management/recovery material — password in keyring only, no restic key add/change/list.
Off-site: 12 no remote backend — path picker only, rejects paths under home; S3/SSH/B2 impossible.
Retention: 13 manual backups never prune (thin only with --scheduled); 14 no prune preview.
Scheduling: 15 missed catch-up run fails silently (Persistent timer no RequiresMountsFor/retry); 16 two conflicting schedule stores (GSettings dead, drop-in 12:30); 17 linger/home-snapshot time unfixable in UI.
Notifications: 18 no proactive backup notifications (timer units no OnFailure).
Shell-specific: 19 local-snapshot restore gated on external drive — BackupPanel.qml:106,116 enabled: Backup.driveSetUp but timeline from local home list; with snapshots but no drive every restore button dead; 20 sizes always zero (s.total_size never returned by home list) and selected snapshot lost (Backup.qml:37-44 ignores name).

## Data portability formats (agent ses_dfb8c3a55ffe50FUxF4vKMMisN)

Capability matrix: Contacts imports vCard 2.1/3.0/4.0 + images, exports vCard 4.0 only (missing CSV, LDIF, vCard 3.0-out); Agenda ICS VEVENT import, no export; Feeds OPML in/out flat (missing JSON Feed, category-preserving OPML, read/starred export); Mail no import, decoded MIME/source out; QuickNotes HTML-in-pre/print out; Photos import 9 image exts, no export; VideoTrimmer 5 video+opus in, mp4/opus/png out; VoiceRecorder opus/flac/wav; Passwords GPG only; Tasks no formats; Terminal own JSON; WebApps .desktop one-way; Clipboard image/text; Screenshots PNG/clipboard/OCR.
22 ranked gaps with evidence: 1 Contacts no CSV; 2 vCard export hardcoded 4.0; 3 no LDIF; 4 Terminal no ~/.ssh/config import; 5 key import blind cp fails on .ppk; 6 VoiceRecorder no MP3/AAC; 7 VideoTrimmer no EDL/cut-list; 8 output container fixed .mp4; 9 QuickNotes HTML not rendered; 10 no PDF export; 11 Music no m3u/pls; 12 Calendar no export; 13 Mail no .eml save; 14 no mbox/Maildir export; 15 Photos no XMP/IPTC; 16 no Google Photos Takeout JSON; 17 no export-selection copy-out; 18 Feeds no JSON Feed; 19 OPML export drops read/starred; 20 Tasks zero file formats (todo.txt etc); 21 WebApps no import/export; 22 Screenshots OCR/formats clipboard-only.

## FilePicker & handoff UX (agent ses_dfb8bde56ffeMRFAt4xiNkyHq5)

Picker thin overlay: sidebar Files.places only, list FileDirectory (watch+name filter), save bare TextField; no per-picker search/preview/mkdir/sort/view/path typing/context menu. Portal maps OpenFile/SaveFile/directory correctly (Portal.qml:24).
1. No search field though model supports query/refilter (FileDirectory.qml:22,73-83; picker never sets it).
2. Save mode never confirms overwrite (canAccept only validName).
3. Wildcard MIME filters from Flatpaks degrade to show-everything (portal.py:86-89 image/* → no extensions → filters=[]).
4. Picker-initiated saves/exports give no feedback (Contacts.qml:142-152 FileView printErrors:false; Feeds.qml:78 fires blind).
5. Drag file from picker impossible (rows MouseArea-only, no Drag mime data).
6. Portal dialog neither modal to requesting window nor placed on its output (portal.py:125 discards parent; picker Ui.closeAll + focusedOutput).
7. No file preview/Quick Look in picker (KeyFocus peekable exists but picker rows default false).
8. No Recent/Starred place in picker sidebar (virtual places exist in Files but unreachable).
9. No show-hidden/sort/view controls.
10. No path-bar editing Ctrl+L (breadcrumbs click-only; FolderPicker has typed field).
11. Portal writable hint dropped (portal.py never reads opts["writable"]).
12. No default extension appended in save mode.
13. No create-folder affordance.
14. Multiple selection offered when multiple:false then truncated.
15. "Open with"/"Edit" don't hand file to right app (Share.qml gio open; FileActions → Chronoa says "open file" to LLM).
16. No reveal-containing-folder from share sheet/picker.
17. Open-with picker can't set default.
18. Read errors look like empty folder.
19. Keyboard nav gaps (no Backspace-up, no type-to-select).
20. No recent save locations or filename autocomplete.
Highest value × ease: #1–#4. #11 needs live portal confirmation.

## CLI & terminal tool depth (agent ses_dfb8b85c1ffeHYGSR72Jd4ac7C)

CLI:
1.1 shani media next/stop/previous/toggle silent no-ops — GROUPS empty args, IPC_NAMES maps to "media" but shell function media(action) never gets action. [FIXED this pass: arg literals passed through]
1.2 advertised --json mode doesn't exist (docstring bin/shani:5,11,14 but build_parser has no flag).
1.3 most app operations no CLI verb (feeds/mail/photos/contacts/translate/backup/firewall/nearby/disks/passwords/etc).
1.4 no dry-run, verbose, config file, version.
1.5 argument handling unchecked/dead (unused needed with precedence bug; numeric args raw strings; stdin truncated 12000).
1.6 wiring test can't catch 1.1 (checks function name not arity).
Terminal emulator: 2.1 Connect spawns TTY-less process (execDetached ssh/picocom vs Files.openTerminal via xdg-terminal-exec); 2.2 no per-app terminal; 2.3 Settings monospace font never reaches terminal; 2.4 transparency hardcoded; 2.5 only foot themed.
SSH: 3.1 host groups/tags promised in header but absent; 3.2 no ~/.ssh/config import; 3.3 no multiplexing/ControlMaster; 3.4 no host-key management (accept-new forced); 3.5 tunnel list no liveness status; 3.6 agent forwarding config-only; 3.7 key list display-only and resolves to public key (.ssh typo in name parser); 3.8 RSA-2048-only, no passphrase.
Snippets: 4.1 clipboard-only (no variables/Run/import/export, stored in 0644 settings.json); 4.2 no command-completion notification (OSC 133 marks emitted but nothing listens).

## Interactive diagnostics depth (agent ses_dfb8c63ebffeC5IxeHkGq76onE)

Tier 1: 1 health ring ignores failed user units (health-check.py:52 systemctl --failed no --user); 2 Disk column lifetime total not rate (Processes.qml:377,453 + TopProcesses:156-178 cumulative /proc io); 3 Follow mode yanks reader to newest (LogsPanel.qml:84-89 re-reads every 3s); 4 Problem report no redaction controls (system-report.py:57 prose warning, hostname/lspci/200 journal lines); 5 no time-range window in Logs (-n 200 only); 6 health one-shot no trend; 7 category chips regex heuristics not journal sources, audit logs never read; 8 no bookmarks on log entries; 9 search literal substring only.
Tier 2: 10 per-process network dead placeholder (nethogs probed never launched, no ss/lsof/proc/net reader); 11 shell never surfaces shani-health CLI flags; 12 graph history ~3min memory-only; 13 per-core instantaneous only, GPU one nvidia-smi line; 14 threads a count not a view; 15 benchmark thin (64MiB read-only); 16 health scoring unweighted; 17 report no structured form; 18 log details raw JSON.

## Fixes applied this pass

- shani media next/stop/previous/toggle now pass their action literal to media(action) (were silent no-ops).
- tests/test_cli_ipc.py updated to accept lowercase literal args (the fixed-action mechanism _run_group uses).

---

# Twelfth pass — full reports

## Containers/virtualization depth (agent ses_dfb849f69ffes7jsIrMkKcbY8T)

Scope: ContainersWindow.qml, bridge/containers.py, tests, dev scripts, Cassini tabs, docs. What exists: 389-line window, three tabs (Toolboxes/Containers/Images); Distrobox create/enter/upgrade/export/remove; Podman list/start/stop/restart/remove/logs/image-remove/prune; rootless.

1. No custom image — four hardcoded chips (ContainersWindow.qml:24-29).
2. No name field — nextName() auto-generates ubuntu, ubuntu-2.
3. Podman containers have no shell entry — enter() always distrobox enter; for !c.box run xdg-terminal-exec podman exec -it.
4. Export one-way — box-export --app only; no unexport/list of exported apps.
5. No Podman container creation — only management verbs; docs promise podman run -p/-v.
6. No home/path choice — distrobox create passes only --yes --name --image.
7. --nvidia/--init/--ephemeral/--root absent though GPU containers documented.
8. No --additional-flags/--mount/--env (shlex imported but unused).
9. Logs one-shot (--tail 300 static string), no follow.
10. App list scans only /usr/share/applications and plain Name=, misses user apps/locales.
11. No resource limits or stats (no podman stats, no --cpus/--memory).
12. No update-all or image-update signal.
13. Toolboxes detected by Podman label only — union with distrobox list.
14. No snapshots (commit/restore).
15. No file-manager integration ("Open its home").
16. No .desktop generation or icon-theme control for ordinary Podman GUI apps.
17. No compose support (docs teach podman-compose).
18. No Settings defaults (distro choice transient).
19. No handover between shell Containers and Cassini inventory.
20. Tests narrow and fake-only; env overrides unused.
Docs overclaim: "Pods pre-installed on every edition" and "BoxBuddy pre-installed" describe external apps the shell only imitates.

## Bluetooth/OBEX transfer depth (agent ses_dfb84cadcffeDfeNknQT7225t9)

Shell-fixable:
1. No auto-accept for known/trusted devices (obex-agent.py:99-109 asks every push).
2. No receive progress and no cancel (BytesTransferred ignored, Transfer1.Cancel never called).
3. Ignored push hangs forever (notify-send -A implies --wait, no -t; shani-link twin has DECIDE_SECONDS=60).
4. No destination picker per file (target fixed at authorization).
5. No Bluetooth transfer history (received counter + last path only).
6. Outgoing send no progress/cancel/resume/retry (BtSend.qml polls Status only, 600 iterations).
7. One file per send (single file string, one SendFile).
8. Send does not connect paired-but-disconnected device.
9. HFP call-audio routing exists in bridge (bt_telephony.py:224-249 audio_route) but no shell UI.
10. PBAP call history implemented in shani-link but not reachable from shell.
11. No FTP/browser of phone files.
12. No per-device auto-connect (one global switch, regex /^(audio|input)/ excludes phones/watches).
13. Connection profiles not exposed (UUIDs read but no profile chips).
14. Trust set before pairing succeeds (SidebarDetails.qml:157).
15. No device rename/alias.
16. Pairing prompts no timeout (ask waits indefinitely).
17. Default agent answers pairings it did not start.
18. Single OBEX agent slot with no handoff.
Needs BlueZ/hardware: no NAP server/obexctl/sdptool/pand/rfcomm; FTP support unconfirmed; Android PBAP/MAP consent external; A2DP↔HFP auto-switch needs WirePlumber policy.
Risk: shell's outgoing OBEX send path has no test at all.

## Authenticator, Password Generator, Kundali depth (agent ses_dfb847481ffe9n1Er4WlI70qOl)

19 gaps ranked. Top: 1 Panchang computes 15 fields, UI shows 5 (masa/paksha/ritu/ayana/years/sun-moon longitude dropped); 2 no HOTP (explicitly rejected, test pins it); 3 no strength estimate (zxcvbn); 4 no dictionary/pattern rejection (Password1! passes); 5 no sunrise/sunset or tithi end times (helper hardcodes 06:00/18:00); 6 no dasha/antardasha (helpers exist unreachable); 7 no muhurta selection (muhurta_score exists, no CLI/UI); 8 no clock-drift correction; 9 passphrase wordlist uncurated system dictionary; 10 no history/favorites; 11 Vikram Samvat approximated as year+57; 12 YubiKey OATH shallow (period 30 forced, HOTP skipped); 13 no horoscope matching/gun milan; 14 no planet→house mapping/divisional charts; 15 no Steam Guard format; 16 no camera QR scan; 17 no single-use backup-code storage; 18 no auspicious-time reminders; 19 no autofill handoff.
Risk: shani-chronoa dasha/muhurta/varga helpers simplified ("sunrise_approx=06:00") — label values approximate.

## WebApps/PWA depth (agent ses_dfb83f53cffewCWLBe9sqkGoly)

Shell-fixable: 1 tapping a web-app row DELETES it, no open/edit [FIXED this pass: row opens via WebApps.open, explicit ✕ removes]; 2 no URL validation/secure-context/warning (http/file/javascript/data accepted); 3 no per-app refresh/cache/site-data clear; 4 no launch-by-name IPC (comment promises but only add/remove exist); 5 web apps never under launcher Internet chip (Network alias missing); 6 no edit/rename/reorder/schema/dedupe; 7 sanitized-name collisions overwrite; 8 no open-at-startup; 9 no dock-pin/workspace-assign action; 10 no per-app keyboard shortcut; 11 feature undocumented.
Browser-level: 12 no PWA install pipeline beforeinstallprompt/manifest; 13 no service worker/offline start; 14 push notifications bypass shell (portal Notification unimplemented); 15 per-app permissions/quota not expressible; 16 web-app UX actions browser-side/unreachable; 17 icons dir allocated but unused so uninstall cannot be clean.

## Keyboard shortcut conflicts/discoverability (agent ses_dfb841ecaffeN4gYGad1ojrI7n)

Negative result: no direct niri-vs-app same-combo collision in shipped config (globals use Mod, apps use Ctrl/bare). Conflicts from customization/within app layer/unteachability.
1. OSK cannot send Super/Meta — all global shortcuts touch-unreachable (Osk.qml ctrl/alt only).
2. Custom binds can silently break Ctrl+C/V/Z/S (takenBy checks only niri binds).
3. Annotate bare E clear unrecoverable (undo only pops one stroke).
4. No surface lists app-internal shortcuts (Viewer ~20, Files ~30 nowhere).
5. Calculator window-level Return/Enter Shortcut overrides focused TextFields.
6. Escape no-op in TextEditor with >1 tab.
7. Mutation modifier inconsistent (Annotate bare Z/E/S, Whiteboard Ctrl+Z, Trimmer I/O/S, PdfReader R/F/W/P).
8. Shared KeyFocus no Home/End/PageUp/PageDown.
9. Launcher Ctrl+Y Quick Look undocumented.
10. "Change keyboard shortcuts" lands far in Settings.
11. Escape means four different things across surfaces.
12. Three-key a11y combos no one-handed path.
13. Redo combos diverge (Files/TextEditor both, WindowLayouts undo only).
14. Shortcut-search skips custom binds.
15. Mod+Escape shortcuts-inhibit no discoverability.

## niri integration & extensions (agent ses_dfb83c98dffeaLwdDXNyVVpmRT)

Verified niri 26.04 action list. Already exposed: screenshot-window, focus-window-or-workspace-*, dynamic cast, unset-workspace-name, close-window+force-close, global focus-follows-mouse.
Shell-exposable: 1 no third-party extension surface at all (every widget literal LazyLoader, no manifest dir) — the structural Waybar/Plasma/GNOME-extension gap; 2 hand edits to shell-owned includes destroyed (WindowRules regenerates whole file); 3 no diff/history/manual restore for config (one .prev deleted on success); 4 preset width/height actions KDL-only; 5 toggle-keyboard-shortcuts-inhibit unreachable outside KDL; 6 screenshot-window fires blind at focused window, no window-menu capture; 7 column-level moves/swap absent; 8 no apply-config-without-restart (niri load-config-file unused); 9 urgency display-only (set/unset-window-urgent unused); 10 niri pick-window unused; 11 single-socket assumption breaks nested sessions; 12 focus-navigation actions unused; 13 workspace rename monitor-warping and index-only; 14 toggle-window-rule-opacity unused; 15 niri msg layers unused; 16 IPC discoverability for extensions absent.
Compositor-level out of scope: per-workspace focus-follows-mouse, drag-to-edge, gestures, always-on-top, thumbnails, Activities, colour management, per-output VRR, session manager, XWayland scaling.

## Context menus depth (agent ses_dfb84453dffeUyEoWFBA2qYJ1c)

Structural: no shared context-menu component and no Menu{}/Popup{} anywhere in ~93 modules. Every menu hand-rolled Glass+Repeater+Rectangle+KeyFocus. Only Files, Dock, desktop icons and bar app menu have real menus; KeyFocus wires Menu/Shift+F10 but only 8 call sites set menuable:true.
1. Files menu never takes keyboard focus on open (no Ui.focusFirst, Dock does).
2. Escape doesn't dismiss Files menu.
3. Files menu items invisible to screen readers (no Accessible role/name/onPressAction; Dock gets it right).
4. Files file menu mouse-only — no long-press.
5. No text-editing context menu anywhere (TextField raw TextInput, 3 TextEdits) — no Copy/Cut/Paste/Select All/Undo/Redo. Highest value.
6. No shared context-menu primitive (root cause of 1-3,18).
7. TextEditor tabs no menu.
8. Photos tiles no menu.
9. Mail message rows no menu.
10. Viewer right-click/long-press only rotate — no image menu.
11. Music library rows no menu.
12. Calendar events no menu.
13. Contacts rows no menu.
14. Feeds rows no menu.
15. Tasks rows no menu.
16. Terminal host rows no menu.
17. PdfReader no page/selection menu.
18. Menu presentation inconsistent (icons/separators/submenus).
19. Bar right-click actions mouse-only (no Hold on Chip).
Comparison: GNOME/GTK4 gives every entry GtkPopoverMenu; KDE Menu/MenuItem; macOS NSMenu; iOS long-press. Shani has scaffolding but almost no menus.

## Test finding (agent a11y test)

A new static a11y test (tests/test_qml_a11y.py) found ~84 IconButtons with no tip or Accessible name across the shell — real AT-SPI gaps, recorded for triage (not fixed in this pass).

## Fixes applied this pass

- WebApps settings row no longer deletes the app on click; row opens via new WebApps.open(name), explicit remove button.

---

# Thirteenth pass — full reports

## Undo/redo consistency (agent ses_dfb773400ffeh2qv8kyZPupP8c)

Destructive single-click zero undo: 1 Photos Move to trash bypasses Files undo stack (PhotosWindow.qml:418-421 → Viewer.trash() gio trash directly, no pushUndo) — highest value; 2 Mail delete one click, no confirm/undo, hits IMAP; 3 Calendar event delete one click writes EDS; 4 Feed subscription Remove no confirm/undo; 5 SSH host delete no confirm/undo; 6 Web-app remove no confirm/undo.
Two-tap but no undo: 7 Contact delete (4s); 8 Authenticator key remove unrecoverable; 9 App uninstall/AppImage remove; 10 Container/image remove + unconfirmed prune; 11 Process KILL no undo; 12 Clipboard wipe irreversible; 13 Notification Clear all; 14 Automation rule removal immediate.
Multi-step: 15 Folder sync no undo/backup-dir; 16 PDF merge no undo; 17 Trimmer segments no undo; 18 Settings Undo resets to sign-in snapshot not previous state, vanishes after restart, no Ctrl+Z.
Cross-cutting: 19 Undo affordances inconsistent (Files Ctrl+Z/Shift+Z/Y, TextEditor full, Whiteboard Ctrl+Z no redo, Annotate bare Z, WindowLayouts undo-only, Settings button-only; timers 3s/4s/7s); 20 Toast Undo fragile/inaccessible (5s, no KeyFocus/Accessible name, Files undo bar 7s no announce, all in-memory, cross-app undo impossible, none survives restart).

## External service integrations (agent ses_dfb7708bcffed74iiwTMJZ6A1N)

What exists: shell is standard freedesktop Notifications daemon; only HTTP listener is bridge/serve.py folder share; only true webhook is shani-chronoa channel_bridge.py (Telegram/WhatsApp); no MQTT/HA/GitHub/GitLab/Slack/Discord/Matrix refs.
Shell-fixable: 1 no shani notify TITLE BODY CLI (scripts/phones must use raw gdbus/notify-send); 2 no authenticated inbound webhook (serve.py GET/PUT only); 3 no remote ICS subscription; 4 Mail no new-message alert (no IMAP IDLE); 5 Share can't upload/POST to cloud; 6 no machine-readable shell event stream (battery only notify-send, hooks 6 closed events); 7 no generic secret/token home for integrations; 8 Feeds can't accept WebSub push.
Needs service/account: 9 no Home Assistant/MQTT; 10 no GitHub/GitLab; 11 no CI status surface; 12 messaging only Telegram/WhatsApp; 13 no ntfy/Gotify/Pushover subscriber; 14 Mail OAuth2; 15 no public HTTPS endpoint; 16 cloud share links need account; 17 no cross-device clipboard push bridge.
Risk: #2/#9 turn external input into shell action — ship HMAC/auth + loopback binding first or an open webhook becomes unauthenticated sh -c via Hooks/Automations.

## Macro/scripting automation depth (agent ses_dfb76d2c2ffeRap0DVYJaxBngW)

What exists: 3 authoring surfaces all producing raw sh -c strings in settings.json (rule engine, 5 hook fields, keybinds KDL) + hidden Nautilus scripts loader; execDetached fire-and-forget; no recorder/runtime/event object/visual builder.
1 No macro recorder/replay; 2 no named/addressable macro; 3 hook event object empty/inconsistent (only wallpaper gets args, $2 screen always "", others no context); 4 no scripting language/SDK (29 .js files static QML imports); 5 no GUI macro builder; 6 rich shell state no documented script API (state() volatile test dump); 7 colorGeneration hook orphaned from GUI; 8 Nautilus Scripts hidden/undocumented (the only true event object via NAUTILUS_SCRIPT_* env); 9 execDetached prevents sequencing; 10 no shell-state write contract; 11 no IPC discovery; 12 IPC arg-splitting breaks structured data; 13 hook cascade unbounded (dark→wallpaper hook, only rules have edge guard); 14 scheduler rule-only daily-minute; 15 inline scripts no file-backed hook directory; 16 no keystroke/click replay; 17 no macro test format.
Risk: any recorder/SDK widens already-unpermissioned sh -c path; sequencing + reentrancy should land first.

## Default apps / associations (agent ses_dfb769a7dffehNLWaCjBxIAmvE)

Direct answers: 25 claimed MIME types have no default; common types with no default include text/vcard, application/ics, x-yaml/toml/css/javascript/x-desktop, message/rfc822, OPML/m3u, rar, x-eps, cb7, fb2, XPS; core-type defaults exist for Text Editor/Image Viewer/Media Player/Document Viewer/Archives but NOT Photos/Feeds/Mail/Calendar/Contacts/Fonts (Photos/Feeds/Mail claim zero MIME types); Settings changes per-user partial and xdg-open paths may bypass; per-user only no reset; 8+6 kinds vs KDE full per-MIME.
1 25 claimed types no default (generate from APPS); 2 text/csv default OnlyOffice not our Text Editor; 3 Settings updates only 1-4 of a type's siblings (skel sets 22/28/~70/~80/11); 4 refresh() reads only types[0]; 5 Settings changes may not reach xdg-open paths (xdg-utils 1.2.1 unreliable per shell's own comment); 6 no reset/system default/CLI; 7 no Settings row for most types (Archives/Contacts/Calendar/ebook/font/torrent/OPML/Office/schemes); 8 six removable-media rows dead UI; 9 ISO skel defaults media to Amberol/Celluloid not installed; 10 only niri skel validated; 11 Photos/Feeds/Mail not image/OPML/rfc822 handlers; 12 playlists no handler/default on niri; 13 application/x-desktop no default; 14 no per-type Open With persistence; 15 stale torrent comment; 16 choose() no failure feedback.
Risk: fix #3/#5 together — expanding type lists without fixing xdg-open resolver makes Settings correct while some launch paths still open old app.

## Offline-first per app (agent ses_dfb76734dffeekyW96B2WMBa0t)

Per-app matrix given for 19 apps. Already good: Feeds cache-first reader; Contacts/Photos/Camera/VoiceRecorder/Backup fully local; Software AppStream cache; shani-link cached threads.
Ranked gaps: 1 Mail loses offline mail entirely (no cache, compose clears on Send); 2 Weather blank on cold offline start (forecast memory-only); 3 Radio wipes list on any fetch error; 4 LiveTV re-fetches playlist every open, no channel cache; 5 Calendar writes can vanish (EDS failure → Chronoa ask → toast); 6 Chronoa prompts dropped offline; 7 shani-link texts dropped when device unreachable; 8 Models can't distinguish ollama missing from none installed; 9 Software ratings lie offline (ODRS [] → 0 stars); 10 Updates failure indistinguishable from up-to-date; 11 Maps retries failed tiles no backoff; 12 Nearby send no devices silent no-op; 13 Feeds no cache age shown; 14 Chronoa/Translate no offline dictionary fallback.

## Inclusive design depth (agent ses_dfb764876ffeas3T6i5EhHcjXh)

16 new gaps (tone/terminology from pass 8 skipped): 1 Undo-capable Toast used in exactly one window (Common/Toast.qml built, only SettingsWindow uses) — highest value/ease; 2 destructive IconButtons visually identical (no danger property); 3 Erase danger vs Format neutral inconsistency; 4 Calendar identity color-only; 5 SMART raw mono dump no plain-language summary; 6 tooltips leak kernel internals; 7 urgent windows red rectangle only; 8 delete glyph inconsistency in Notes; 9 edit-clear-all means four things; 10 Advanced progressive-disclosure barely used; 11 treemap small tiles color-only; 12 silent success on Mail/Feeds state changes; 13 Kundali "(R)" unexplained; 14 dead-end playback error; 15 "e.g." inconsistency; 16 untranslated destructive labels.

## Test infrastructure & CI (agent ses_dfb761c0dffezhYY3NrJNjwhEv)

Counts: 152 pytest files / 953 test functions, 46 parametrize; ~88 pure source-string (58%), ~18 bridge behavior, ~34 mixed, ~12 other; full-shell IPC ~1067 result call sites, 17 SKIP; 7 perf budgets; 49 render captures / 261 surfaces; a11y ~20 surfaces conditionally skipped; 50/152 files silent skip guards. Fakes cover all 32 external tools.
1 CI runs zero shell tests (no .github/workflows in shani-shell; reusable test.yml never called); 2 skips count as green (check.sh greps passed/failed only); 3 unit suite runs on host outside test image; 4 perf budgets excluded from default all; 5 a11y checks silently skip without shani-testbed (static test found ~84 unnamed IconButtons); 6 real network dependency with SKIP fallback (open-meteo, no fake); 7 Color Picker has no test at all; 8 four apps only opens-no-error checks; 9 Backup create/restore no behavioral test; 10 permission boundaries untested (suite runs as root); 11 sibling-repo tests skip silently, missing /desk mount unchecked; 12 timing-dominated shell suite (379 waitfor + 447 + 325 sleeps); 13 real D-Bus/process races in pytest; 14 no positive controls for ~88 string checks; 15 render checks never gate CI; 16 flaky fixed-duration media waits.
Strengths: trash/destructive paths well covered; all external tools have fakes; render coverage source-derived and IPC-guarded.
Risk: 88/18/34/12 split is heuristic grep classification.

## Fixes applied this pass

None (research only). A new untracked static a11y test (tests/test_qml_a11y.py) found ~84 unnamed IconButtons; left untracked because it would break CI until those labels are added.

---

# Fourteenth pass — full reports

## Power / suspend / hibernate hardware depth (agent ses_dfb6f337bffeXUI14PH6oz5I6A)

Skipped all listed power items and session-lifecycle suspend findings. Static only.

Shell-fixable: 1 Hibernate delay never configured (HibernateDelaySec exists nowhere; docs tell users to hand-edit sleep.conf); 2 no critical-battery action tied to suspend (15%/7% warn and lock but no hibernate/shutdown fallback); 3 hibernate/resume untested end-to-end (zero testbed probes); 4 two unsynchronised WoL controls (wakeup.py sysfs vs Net.qml NM magic packet); 5 WoL changes not applied to live link (no nmcli device reapply); 6 no RTC wake alarms/wake-to-alarm (rtcwake absent; suspended machine misses calendar alarms); 7 no pre-suspend/post-resume hardware hooks (Hooks has 6 events, no PrepareForSleep); 8 secondary internal batteries ignored (only displayDevice); 9 hibernate has no confirmation while suspend does; 10 hibernate capability checked once at startup; 11 power menu mislabels sleep style (always "Suspend"); 12 docs name nonexistent key HandleLidSwitchExternalMemory (should be ExternalPower).
Firmware/install: 13 swap can be smaller than RAM and deploy shrink invalidates resume_offset; 14 cloud images cannot hibernate silently; 15 sleep state left to firmware/manual tmpfiles (no deep default); 16 power-button long press/double tap unsupported.
Comparison: GNOME/KDE cover basic actions + critical-battery policy but also lack HibernateDelaySec UI; macOS/Windows add RTC wake and modern-standby timing.

## Btrfs snapshot management UI depth (agent ses_dfb6f6794ffe8lnkqAVvpAu29P)

Scope: shani-backup home snapshots + shani-deploy blue-green system snapshots (distinct from predeploy HOME snapshots already filed).
1 Docs teach nonexistent CLI verbs (home create/delete vs home snapshot/remove) — fix docs, regenerate stubs; 2 shell restore footer "Changed files are overwritten" is false/dangerous (GTK copies to dated sibling); 3 Find a File skips all dot-directories (.config/.local/.ssh unreachable); 4 no unified snapshot timeline (shell home + Cassini raw subvolumes + Boot & Recovery slot backups are three disjoint views); 5 manual snapshots cannot be named; 6 per-snapshot size absent; 7 slot backups listing-only with no restore action; 8 no in-app snapshot file browser; 9 no per-snapshot pin (prune deletes oldest by name); 10 snapshot validity never checked (partial/corrupt subvolume looks healthy); 11 boot count/tries never shown; 12 no true revert (restore always creates dated copy); 13 two competing snapshot models (Cassini raw vs home timeline); 14 shell restore no confirmation and closes before opening GUI; 15 whole-/home snapshot scope undisclosed; 16 slot rows raw blue/green no friendly label; 17 script comment names wrong opt-out key.
Risk: items 7/11 need backend work; rest UI/docs-only.

## Boot / splash / first-boot UX (agent ses_dfb6f960effeVUTa0KIKPZBUzE)

What exists: Plymouth bgrt theme (firmware logo + spinner), quiet/splash cmdline, no account at install (vendor wizards for GNOME/Plasma/COSMIC; ShaniOS wizard for niri), automatic slot rollback, no graphical recovery UI.
Shell-fixable: 1 update entry point raw terminal (pkexec shani-deploy, no progress/ETA/phase); 2 account creation one undifferentiated "working" state (6 sequential steps); 3 no "welcome" page on GNOME/Plasma/COSMIC; 4 orphaned-home warning console text only; 5 "Signing you in…" bare status; 6 no boot-time readout (shani-health boot time unsurfaced).
Installer/firmware/docs: 7 no boot progress at all (static logo indistinguishable from hang); 8 impossible docs instruction ("remove splash from cmdline" — embedded in signed UKI, editor disabled); 9 recovery messages invisible under splash; 10 slot-switch notice hidden by design; 11 first-boot script claims console output it never writes; 12 no disk-unlock recovery-key UX at prompt; 13 no hardware detection/driver prompt at first boot; 14 Plymouth updates mode never used.
Comparison: Windows WinRE + BitLocker key escrow; macOS Cmd-R recovery + progress; Ubuntu plymouth text + recovery entry; SteamOS branded animation vs Shani's OEM bgrt looking unbranded.

## D-Bus shell surface as third-party API (agent ses_dfb6f041fffeQMoGWm66bkIbX7)

Architecture: (a) shell's own API is Quickshell IpcHandler (521 functions) over private socket; (b) actual D-Bus names owned only by Python bridges ("Quickshell cannot export a D-Bus object"); no org.shani.Shell interface at all.
Security (high value, low effort — mostly one sender check each): 1 any session process can drive every shell function (lock/poweroff/settings) with no polkit/peer check; 2 Agent Approve bus-wide — malicious app can approve its own tool calls; 3 UI spoofing via Mascot.Show/Windows.Cue; 4 any process can lock/reset idle/prevent locking; 5 dev.shani.Link exposes contacts/call history/dial/notifications/location to any bus client; 6 portal OpenFile returns user-chosen paths to any caller.
API design: 7 no D-Bus Properties for shell state (only pull-only state() JSON); 8 no D-Bus signals for shell events (external apps must poll); 9 no service activation for most names (only portal has .service file); 10 bus names/paths undocumented as stable API; 11 no versioning/deprecation; 12 all bridges use BusNameOwnerFlags.NONE no replacement policy; 13 Flatpak reachability undefined (no name manifest); 14 relay contract payloads undocumented; 15 portal FileChooser-only; 16 no caller identity exposure.
Comparison: GNOME publishes documented org.gnome.Shell; KDE versioned org.kde.* with introspection; sway documented versioned IPC. Shani has private unversioned socket + undocumented compat names.
Risk: #2/#5 may be intentional bus-wide design — confirm with owners before hardening so legitimate peers aren't locked out.

## Chronoa backend under-exposure (agent ses_dfb6fc40affev9Y7uLv7LIyE9D)

1 Structured tool arguments thrown away (backend tool/tool_done with tool+args; shell handlers read only e.text); 2 compaction events dropped ("it forgot what I said" indistinguishable); 3 turn-id broadcasts ignored; 4 shell exposes only 4 of ~36 GActions; 5 project folder/Build mode unreachable; 6 MCP server state invisible; 7 inbound channel bridges (Telegram/WhatsApp/LAN) no shell face; 8 entire Chronoa Settings window behind external process launch (~225 schema keys, shell shows enable/kill); 9 Mascot settings no shell control; 10 learned tool priors never reach shell suggestions; 11 search provider on separate bus name ignored by launcher; 12 usage/cost telemetry no shell surface; 13-18 lower value (answer-question, setup pages, voice-clip health, cloud STT, transcribe-file, rail toggles).
Risk: items 4-9 assume bridge actions can be dispatched generically — allow-list required because ActivateAction passes no parameters.

## Niche/commercial desktop comparisons (agent ses_dfb6ed859ffeebiLGGrRHe71z1)

New QML-deliverable ideas: 1 Cinnamon panel edit mode + applet manager (bar widgets toggle but not reorder); 2 taskbar-style per-window list in bar (Niri.windows exposes ids); 3 app-grid edit mode — reorder/hide/folders (tvOS/Tizen); 4 tvOS Top Shelf focused-app hero preview; 5 Kodi Continue Watching row (PlayQueue resume points exist); 6 Batocera game library with box art; 7 Garuda network assistant guided troubleshooter; 8 Garuda upgrade-adviser "needs attention" card; 9 unresponsive-app watchdog Wait/Force Quit (System Monitor polls /proc); 10 ChromeOS combined clock+calendar+notifications tray; 11 ChromeOS lock-screen accessibility dock; 12 Kodi profiles on shared TV; 13 Clear Linux verify & repair; 14 Pantheon starred files virtual folder; 15 external media "index/play" prompt; 16 screenshot/record in power menu.
Out of scope: visionOS gaze, SteamOS controller layouts/fan curves, Tizen bezel/HDMI-CEC, webOS Magic Remote, postmarketOS charging/emergency call, Manjaro kernel switching, NixOS generations, Garuda cloud sync/retroachievements, Tizen multi-view/PiP.

## Shani Link GTK app features not surfaced in shell (agent ses_dfb6fec14ffemQj14WWvzn9a62)

1 Five of seven GTK pages have no shell entry point (Watch/Radio/NFC/Remote/Background/Screen; shell only --page=phone/contacts); 2 no Link settings UI (14 named switches in GTK Background page); 3 screen mirroring no shell controls (Check/Start/Share window/Stop, Touch toggle, report); 4 watch dashboard entirely GTK-only (steps ring, sleep stages, stress, HR/SpO2/BP, workouts, Find, Sync time); 5 Android USB tools reduced to one share call (GTK has 20+ verbs); 6 phone diagnostics reads unreachable (Notifications/Usage/Line/Wifi/Thermal/Location/Display via D-Bus); 7 live in-call controls missing from Calls (timer, mute, audio picker, DTMF, hold/swap/merge, recording, video); 8 SIP account manager no shell surface; 9 phone music control not in Media Player; 10 received-files list and receive switch missing; 11 shell always picks first device (GTK has per-serial cards); 12 generic BLE/GATT inspector; 13 live FM/SDR radio absent from shell Radio; 14 NFC read/write UI; 15 infrared remote learn/send; 16 pairing wizard QR/passkey flow unreachable.

## Test/verification note

A new static a11y test (tests/test_qml_a11y.py) found ~84 unnamed IconButtons; an agent has begun adding tips/labels to affected files (DatePicker, CameraPanel, ControlCenter, Settings, etc.). Outcomes pending.

---

# Fourteenth pass — VERBATIM agent reports

The section above condensed these. What follows is the complete original text of each agent report, unabridged.

## VERBATIM: Power / suspend / hibernate hardware depth

# Fourteenth-pass research: power / suspend / hibernate hardware depth

Read `GAPS.md` and `GAPS-RESEARCH.md` first; skipped all listed items and the suspend session-lifecycle findings (GAPS-RESEARCH:604-612). Static only — no edits, no runtime. Everything below is new at the hardware-behaviour level.

## Shell-fixable — ranked by value × ease

1. **Hibernate delay is never configured.** `shani/Services/Power.qml:182-194` and `Modules/Settings/SettingsPowerKeys.qml:141-143` offer "sleep, then hibernate", but `HibernateDelaySec` exists nowhere in shani-settings/install-media/deploy — only `shani-blog/posts/shani-os-power-management.md:90-94` tells users to hand-edit `/etc/systemd/sleep.conf`, contradicting `shani-docs/docs/system/power.md:56-58` ("nothing to configure manually"). Sketch: ship `/etc/systemd/sleep.conf.d/50-shani.conf` with `HibernateDelaySec=1800`.
2. **No critical-battery action tied to suspend.** `Power.qml:97-115` warns at 15 %/7 % and auto-locks, but "hibernates when the battery runs low" (comment at `Power.qml:182-184`) is left entirely to logind defaults; nothing sets the critical threshold or a fallback shutdown. Sketch: expose "at 7 %: hibernate if possible, else power off" via the same drop-in as #1.
3. **Hibernate/resume is untested end-to-end.** `GAPS.md:242` defers it to real hardware; shani-testbed has zero hibernate/suspend/resume probes; the only shell assertion is the fallback check at `dev/shell-test.sh:2257-2260`. `power.md:65` tells the user to verify the cycle themselves. Sketch: boot-probe that plants a marker, hibernates and resumes, asserting the marker survives and `resume_offset` matches.
4. **Two unsynchronised Wake-on-LAN controls.** `bridge/wakeup.py:61-63` labels sysfs `power/wakeup` as "Wake-on-LAN (ethX)", persisted by `bridge/shani-admin.py:299-331`; `Services/Net.qml:90-95` separately toggles NM's `802-3-ethernet.wake-on-lan=magic`. The Power-page row never programs magic-packet filtering; the Network-page toggle never sets device wakeup. Sketch: route the network row through `Net.setWakeOnLan()` / one source of truth.
5. **WoL changes never reach the live link.** `Net.qml:92` only runs `nmcli connection modify` — NM applies `wake-on-lan` on device activation. Sketch: `nmcli device reapply` (or reconnect) after modifying.
6. **No RTC wake alarms / wake-to-alarm.** `rtcwake` appears nowhere in the shell. Calendar alarms (`Modules/Calendar/CalendarPanel.qml:231,282,432`) and Chronoa timers only fire while awake; a suspended machine misses them. Sketch: arm `/sys/class/rtc/rtc0/wakealarm` for the next alarm, cancel on edit, add a "wake for alarms" toggle (GNOME Clocks / Windows have this).
7. **No pre-suspend / post-resume hardware hooks.** `Services/Hooks.qml:17-19` fires only wallpaper, dark-mode, lock, unlock, startup, colour-generation. Sketch: add `preSuspend`/`postResume` scripts fed by the logind `PrepareForSleep` bridge (`bridge/logind.py:66-72`) to stop recorders/radios and re-attach devices. *(Distinct from the already-filed "shell jobs don't inhibit idle suspend" — this is hardware prep, not inhibition.)*
8. **Secondary internal batteries ignored.** `Power.qml:15-16` takes percent/time from `UPower.displayDevice` alone, and the peripheral filter at `:23` excludes every `powerSupply` device — a second internal battery is neither aggregated nor shown, unlike GNOME/KDE. Sketch: sum all `isLaptopBattery` devices and add per-battery rows.
9. **Hibernate is the only unconfirmed power action.** `Modules/ControlCenter/SidebarHeader.qml:219-220` skips confirmation for both suspend and hibernate. Sketch: confirm hibernate too (slow write; a failed resume drops the session).
10. **Hibernate capability is checked once.** `Power.qml:196-222` queries `CanHibernate`/`CanSuspendThenHibernate` with `running: true` at startup; enabling swap or resume later leaves the UI stale until shell restart. Sketch: re-query when the power menu opens.
11. **Power menu mislabels the sleep style.** `SidebarHeader.qml:207` always says "Suspend" even when `Power.sleepVerb` is `suspend-then-hibernate` or `hybrid-sleep`. Sketch: bind the label to `Power.sleepVerb`.
12. **Docs name a logind key that does not exist.** `shani-docs/docs/system/power.md:92,120` say `HandleLidSwitchExternalMemory`; the real key is `HandleLidSwitchExternalPower` (which `shani-admin.py:265` writes). Sketch: fix both lines; add the docked action to `power_keys()` (`:263-266` writes only three keys).

## Firmware / kernel / install-level

13. **Swap can be smaller than RAM by design.** `os-installer-config/scripts/install.sh:772-783` warns hibernation "may not be available"; `shani-deploy/scripts/shani-deploy.sh:3733-3782` can shrink `/swap/swapfile` for updates, invalidating the `resume_offset` baked into the UKI (`gen-efi.sh:670-688`) until the next deploy. `shani-health.sh:3905` detects a stale offset but nothing regenerates immediately. Sketch: regenerate the cmdline/UKI after a shrink, or refuse hibernate while stale.
14. **Cloud images cannot hibernate, silently.** `shani-install-media/packer/scripts/01-configure-aws.sh:227` caps swap at 4 GiB, while `configure.sh:965-973` still appends `resume=`. On >4 GiB VMs `CanHibernate` is false with no user-facing explanation. Sketch: skip `resume=` when swap < RAM; report "hibernation unsupported" in health.
15. **Sleep state left to firmware/manual tmpfiles.** `power.md:116-127` instructs users to hand-write `/sys/power/mem_sleep` and a tmpfiles entry; no shipped `deep` default or UI, so s2idle's much higher drain is the silent default on many laptops. Sketch: ship a `deep` tmpfiles drop-in where supported + a toggle.
16. **Power-button long press / double tap unsupported.** `SettingsPowerKeys.qml:156-165` writes a single `HandlePowerKey` action; `Services/InputConfig.qml:92-93` hands the key to niri until configured. Short vs long press is firmware territory and is undocumented. Sketch: document the boundary; expose double-tap via udev/logind only where firmware allows.

## Comparison in one line
GNOME/KDE cover the basic action set and critical-battery policy but also lack a HibernateDelaySec UI; macOS/Windows add scheduled RTC wake and explicit modern-standby/lid timing — Shani's real deficits are #1–7, not the presence of Suspend/Hibernate buttons.

Skipped: suspend-session lifecycle, kill switch, charge limit/threshold, power profiles, thermal sensors, PPD, idle inhibitors, dim overlay, UPS, lid-close behaviour, peripheral-battery warnings (all already filed). Risk: all findings are static; the hibernate/resume and RTC-wake claims in particular need a real S4-capable machine to confirm.

## VERBATIM: Btrfs snapshot management UI depth

Read-only, static pass. I read both GAPS files and skipped every listed item (buttons identical, verification badge, retention, exclusions, off-site, snapshot diff, reinstall/manual btrfs, predeploy home snapshots, notifications, restic). The `pre-deploy` skip refers to `predeploy-*` **home** snapshots; the gaps below about `@slot_backup_*` **system** backups are a different subsystem.

## Ranked gaps (value × ease)

| # | Gap | Evidence | Sketch |
|---|-----|----------|--------|
| 1 | Docs teach CLI verbs that do not exist: `home create` / `home delete` are actually `home snapshot` / `home remove`. | `shani-docs/docs/system/backup.md:60`; `cli.py:170,178`; mirrored in `llms-full.txt:55909` and `doc/system/backup/index.html:253` | Fix two verbs in the Markdown, regenerate stubs/llms. |
| 2 | Shell restore footer promises **"Changed files are overwritten"** — false and dangerous: restore only opens the GTK page, which copies to a dated sibling and never overwrites. | `BackupPanel.qml:131`; `Backup.qml:37-44`; `home_page.py:64-76,79-86` | Change footer to "opens the restore view; a dated copy is placed beside the original". |
| 3 | Find a File silently skips every dot-directory, so `.config`, `.local`, `.ssh` — where app settings live — can never be found. | `home_page.py:324` (`dirs[:] = [d for d in dirs if not d.startswith(".")]`) | Add an "include hidden" toggle; default on for this search only. |
| 4 | No unified snapshot timeline: shell shows home snapshots, Cassini Backup shows arbitrary raw btrfs subvolumes, Boot & Recovery shows slot backups — three disjoint views. | `Backup.qml:20-21,69-86`; `backup.py:122-128`; `boot_recovery.py:365-366,704-724` | Merge `home list --json` + `--list-backups --json` into one tagged timeline in `Backup.qml`. |
| 5 | Manual snapshots cannot be named or labelled; `_name()` hardcodes `kind-timestamp` and the Take Now button passes no name. | `home.py:127-131`; `home_page.py:144-146,293-294`; `cli.py:170` | Optional `--name` on `home snapshot` + an EntryRow next to "Take Now". |
| 6 | Per-snapshot size absent: JSON has only `(name, path, whole)`; GTK rows show date and subtitle but no size. (Shell's zero-size is already logged; the contract and GTK page still lack it.) | `home.py:67-70`; `cli.py:60`; `home_page.py:227-252` | Add `size` to `list_for` (`du -sh`/qgroup cache) and render in the row subtitle. |
| 7 | Slot backups are listing-only — no "restore this backup", so a generic rollback cannot target an older backup than the newest. | `boot_recovery.py:704-724`, `ABOUT_NOTE :132-136`; `updates.py:162-167,479-507` | Add per-backup action calling a deploy `--restore-backup=<name>` flag, or at minimum state which backup the generic rollback will use. |
| 8 | No in-app snapshot file browser: every "Browse" hands off to an external `Gtk.FileLauncher`. | `home_page.py:242-246,262-263` | Embed a read-only tree over `s.path` with per-file "Restore". |
| 9 | No per-snapshot pin: pruning deletes oldest by name with no way to protect one valuable snapshot (per-snapshot, not a retention-policy UI). | `home.py:194-209`; `home_page.py:247-251` (only manual removable) | `home pin <name>` marker; `_prune` skips pinned names. |
| 10 | Snapshot validity never checked: `list_for` trusts directory names and the Cassini list only `stat`s the path; a partial/corrupt subvolume looks healthy and is offered for restore. | `home.py:268-296`; `backup.py:283-284` | Cheap `btrfs subvolume show` probe per row → "Unreadable" badge + Remove action. |
| 11 | Boot count / tries (`+3-0`, `triesLeft/triesDone`) is never shown anywhere in the UI, despite being the mechanism updates rely on. | `boot_recovery.py:100-115` (no tries field); `boot_entries.py:265-289` (efibootmgr only) | Read `bootctl list --json=short`; add a "Boot attempts left" row per slot. |
| 12 | No true revert: restore always creates `name (date).ext`, so undoing a change means manually renaming files. | `home_page.py:64-76,384-394` | Offer "Replace original (keep a copy of today's file)". |
| 13 | Two competing snapshot models in one OS: Cassini "Take a snapshot" makes a timestamped sibling subvolume at an arbitrary path, invisible to the home timeline. | `backup.py:134-142,317-319`; `cli.py:135-165`; `home.py:39-45` | Point Cassini's button at `home snapshot`, or label that group "Advanced: raw btrfs" and hide it from Backup. |
| 14 | Shell restore has no confirmation and closes its window before opening the GUI — no chance to reconsider. | `BackupPanel.qml:103-121`; `Backup.qml:37-44` | One `Adw.AlertDialog` naming the snapshot before `restoreFromSnapshot`. |
| 15 | A whole-`/home` snapshot is presented to each user as "Taken by hand" with no hint it contains every account (ACLs keep files private, but scope is undisclosed). | `home.py:158-175,279-295`; `home_page.py:232-241` | Subtitle "Snapshot of all homes — other users' files stay private". |
| 16 | Slot rows are raw `blue`/`green` + version; no friendly label or active/inactive tint in the history list. | `boot_recovery.py:711-716` | Per-slot alias in config, shown beside version. |
| 17 | `shani-snapshot-home.sh`'s own comment names the wrong opt-out key (`deploy_home_snapshot`); the config key is `home_snapshot` under `[deploy]`. | `shani-snapshot-home.sh:16`; `shani-deploy.sh:171,202`; `backup.md:56` | Fix the comment; keep the docs' `home_snapshot`. |

**Skipped / not checked:** snapshot delta/diff, Files "previous versions", all skip-list items (already in GAPS), and no runtime/UI verification — static source and docs only. **Risk:** items 7 and 11 need backend work (`shani-deploy` has no single-backup restore flag and no boot-count JSON), so their ease is UI-only; the rest are UI/docs-only.

## VERBATIM: Boot / splash / first-boot UX

# Fourteenth-pass research: BOOT / SPLASH / FIRST-BOOT UX

Read-only, static. Skipped prior items: safe-mode boot entry, verify-media boot, boot-failure fallback logic, TPM/MOK, setup password/encryption/import, first-boot migration, session chooser. GAPS files are 3,218 lines, not 8,300+ — all thirteen passes were checked.

## What actually exists

- **Splash:** Plymouth theme `bgrt` (`iso_profiles/shared/airootfs/etc/plymouth/plymouthd.conf:2`, `os-installer-config/scripts/configure.sh:656-658`). It is the two-step theme using the firmware BGRT logo plus `spinner` assets (`bgrt.plymouth:50,56`). Boot cmdline is `quiet loglevel=3 splash udev.log_level=3` (`iso_profiles/shared/efiboot/loader/entries/*.conf:4`; installed cmdline `configure.sh:900`).
- **First boot:** no account is created at install (`config.yaml:107-108` `skip_user/skip_region: yes`). Vendor wizards create it (plasma-setup / gnome-initial-setup / cosmic-initial-setup — `shani-deploy/scripts/shani-first-boot.sh:14-15,242-246`); niri instead runs the ShaniOS wizard (`shani-shell/setup/shell.qml:1-6`, pages `welcome,keyboard,network,time,account,chronoa,done` at `:36`).
- **Recovery:** automatic slot rollback plus dracut hooks; no graphical recovery UI.

## Shell-fixable (ranked by value × ease)

1. **Update entry point is a raw terminal, not a progress UI.** `shani/Services/Updates.qml:69-82` hands off to `pkexec shani-deploy` in a terminal with "Press Enter to close". No progress bar, no ETA, no phase text, nothing answering "why is this taking so long". *Sketch:* stream `--status --json` phase into an in-shell progress panel with a "usually 10–15 min, do not power off" line.
2. **Account creation shows one undifferentiated "working" state.** `setup/shell.qml:75,320,1307`; `bridge/first-account.py:105-140` actually does 6 sequential steps (useradd, chpasswd, locale, keymap, timezone, hostname), each up to 60 s. *Sketch:* emit step names over IPC and show "Creating account (2 of 6)".
3. **No "welcome" page on GNOME/Plasma/COSMIC.** Only niri gets the ShaniOS wizard (`setup/shell.qml:1-6`); the other profiles get vendor wizards with no Shani branding, privacy or Chronoa offer. *Sketch:* offer `shani-setup` as the first-login session on all profiles, or at minimum a branded first-run card in the shell.
4. **Orphaned-home warning is console text only.** `shani-first-boot.sh:247-249` tells users to reuse the *same* username or they will not see their files; this goes to journal/kmsg, never to the screen. *Sketch:* detect the orphaned-home condition in the shell and show a one-time dialog after first login.
5. **"Signing you in…" is a bare status.** `setup/shell.qml:301,599`. *Sketch:* "Creating your desktop — first login can take a minute" with a spinner.
6. **No boot-time readout for users.** shani-health measures boot time (`shani-docs/docs/updates/shani-health.md:93`) but nothing surfaces it. *Sketch:* show last boot time on Settings › About.

## Installer / firmware / docs-level (ranked)

7. **No progress of any kind during normal boot.** `bgrt.plymouth:74-76` defines no `UseProgressBar` for `[boot-up]`; progress bars exist only for updates/system-upgrade/system-reset (`:86-112`). Combined with `quiet splash`, a slow boot is a static logo indistinguishable from a hang. *Sketch:* enable a boot-up progress bar/percentage, or drop `quiet`.
8. **Impossible black-screen instruction in the docs.** `shani-docs/docs/install/first-boot.md:83` says "Remove `splash` from kernel cmdline in boot menu", but the cmdline is embedded in the signed UKI and the boot-menu editor is disabled (`docs/arch/boot.md:40,84`; `config.yaml` Secure Boot note). A user staring at a black screen cannot follow this. *Sketch:* replace with "reboot once; if it persists, select the other slot from the boot menu."
9. **Recovery messages are invisible under the splash.** `shanios-recover-default.service:41-42` writes `journal+console`; the boot-failure hook only calls `warn()` (`shanios-boot-failure-hook.sh`). With Plymouth owning the VT, neither reaches the glass. *Sketch:* `plymouth display-message` before the emergency shell and on the post-recovery boot.
10. **Slot-switch notice is hidden by design.** `shanios-boot-success-clear.sh:46-51,63` — "visible only via Plymouth's Escape-key details view; bgrt has no message area of its own" — so an update applying or rolling back is silent. *Sketch:* a 2-second "Now running the new version" overlay on the first boot after a switch.
11. **First-boot script claims console output it never writes.** `shani-first-boot.sh:55-57` says it writes to "journal, the console, and /dev/kmsg", but `log()`/`warn()` at `:63-68` write only stderr + `/dev/kmsg`, never `/dev/console`. *Sketch:* add `printf … > /dev/console` for the "no account exists" warning.
12. **No disk-unlock recovery-key UX at the prompt.** Docs promise "Plymouth presents the passphrase prompt" (`first-boot.md:13`; `arch/boot.md:164-168`) but give no retry count,Caps-Lock indicator, or recovery-key guidance at boot; recovery is a USB + `cryptsetup open` command dump (`arch/boot.md:168`). *Sketch:* add a one-line "Recover with your 48-digit key / backup keyfile" hint in the two-step dialog.
13. **No hardware detection or driver prompt at first boot.** Nothing in `shani-first-boot.sh` probes hardware; docs simply assert everything works (`docs/faq.md:21`). A machine needing a driver/firmware has no first-run signal. *Sketch:* run a passive `fwupdmgr get-devices` / driver probe and show "Everything looks good" or a settings link.
14. **Plymouth's "Do not turn off your computer" mode is never used.** `bgrt.plymouth:86-91` defines an update progress mode, but `shani-deploy` applies updates in the running OS, so the splash never shows an apply-progress screen. *Sketch:* call `plymouth change-mode --updates` before the deployment reboot.

## Comparison (one line each)

- **Windows:** WinRE graphical recovery + BitLocker 48-digit key prompt with escrow; Shani has docs-only recovery and no escrow.
- **macOS:** Cmd-R graphical Recovery + progress bar; Shani's splash is a static vendor logo with no progress.
- **Ubuntu:** plymouth text progress + a "recovery mode" boot entry; Shani suppresses all boot text and has no recovery entry (separate gap already listed).
- **SteamOS:** comparable sealed A/B design, but ships a branded boot animation; Shani's bgrt shows only the OEM firmware logo and the spinner watermark, so on many machines it looks like an unbranded BIOS.

**Skipped / unchecked:** no runtime, VM, hardware, Plymouth-theme or live-deploy verification; no changes made. Risk: items 7–14 need a real UEFI boot to confirm what the splash actually renders — the bgrt theme file inspected was a generated cache artifact.

## VERBATIM: D-Bus shell surface as third-party API

# Fourteenth pass — the shell's D-Bus surface as a third-party API

**Architecture found.** Two distinct planes, never audited together: (a) the shell's *own* API is Quickshell's `IpcHandler` (`shani/shell.qml:258-1218`, 521 functions; `setup/shell.qml:340`), reached only by `qs ipc call shani …` over Quickshell's private IPC socket (`bin/shani:394-406`, `_run_call` :733). (b) *Actual D-Bus names* are owned only by Python bridges, because "Quickshell cannot export a D-Bus object" (`bridge/screensaver.py:4`). There is **no `org.shani.Shell` / `com.shani.Shell` interface at all** (grep: zero hits). Everything below is new vs. the thirteen prior passes.

Ranked by value × ease (top = do first). Static only.

| # | Gap | Evidence | One-line sketch |
|---|-----|----------|-----------------|
| 1 | **Any session process can drive every shell function, no polkit/peer check.** `lock`, `poweroff`, settings, file actions all reachable via one unauthenticated socket. | `bin/shani:394-406`; `shani/shell.qml:258,998`; no `get_sender`/`polkit` in IPC path | Add a restricted D-Bus facade with polkit `auth_admin` for privileged functions; keep `qs ipc` for trusted callers. |
| 2 | **Agent approval bus-wide — a malicious app can approve its own tool calls.** `dev.shani.chronoa.Agent` exposes `Turn/Approve/Write/FindFiles` to any client; `Approve(id,decision)` is literally the user-consent gate. | `bridge/turn_filter.py:3`; `bridge/agent_contract.py:17-44` | Gate `Approve`/`Write` on the shell UI's sender (or a one-time token minted by the panel). |
| 3 | **UI spoofing via Chronoa D-Bus.** Any process can call `Mascot.Show/Scale` and `Windows.Cue(text,hold)` → arbitrary text/noise drawn in the shell's Island. | `bridge/chronoa-bridge.py:67-98,327-387,444-446` | Check `sender` against the known shell/agent peers before broadcasting. |
| 4 | **Any process can lock/reset idle/prevent locking.** `SetActive(true)`→shell lock; `SimulateUserActivity`; `Inhibit` → no auth. | `bridge/screensaver.py:82-94,70` | Restrict `SetActive`/`Inhibit` to known callers; keep `GetActive` open. |
| 5 | **`dev.shani.Link` exposes contacts, call history, dial, notifications, location to any bus client.** `Search/Lookup`, `RecentCalls`, `Dial`, `Notifications`, `Location`, `SipAccount*`, `DeleteCall`. | `bridge/shani_link/service.py:38-140,227-239,484` (handlers take `_sender`, ignore it) | Sender-allowlist (shell + Link app); split read-only vs privileged interfaces. |
| 6 | **Portal `OpenFile` returns user-chosen paths to any caller.** Impl-portal is normally reached via `xdg-desktop-portal` (which does checks); direct callers bypass that and harvest a path. | `bridge/portal.py:100-120,160-175,212` | Verify sender is `org.freedesktop.portal.Desktop` before serving. |
| 7 | **No D-Bus Properties for shell state.** Current workspace, focused window, volume, dark mode exist only as a 200-key JSON blob from `state()` — pull-only, no `PropertiesChanged`, nothing bindable. | `shani/shell.qml:998-1218`; no `org.shani.Shell` anywhere | Export a small `org.shani.Shell` object with read-only properties + `PropertiesChanged`. |
| 8 | **No D-Bus signals for shell events** (workspace change, notification, settings change, app open). The only emitted signals are compat-interface ones (Mascot/Windows, ScreenSaver `ActiveChanged`, MPRIS `Seeked`, Link `CallLogged`/`DeviceEvent`, appmenu `WindowRegistered`). External apps must poll. | `grep emit_signal bridge/*.py`: `screensaver.py:79`, `mpris-player.py:158,171`, `appmenu-registrar.py:59-63`, `shani_link/service.py:227,347,391` | Add `WorkspaceChanged`, `NotificationAdded`, `SettingsChanged`, `AppOpened` on the same facade as #7. |
| 9 | **No service activation for most owned names.** Only the portal has a D-Bus `.service` file; `org.freedesktop.ScreenSaver`, `com.canonical.AppMenu.Registrar`, `dev.shani.Link`, `org.shani.Chronoa.*` are started ad-hoc by shell/process, so a client calling them cold gets `NameHasNoOwner`. | `find data -name '*.service'`: 3 files, only `data/portal/org.freedesktop.impl.portal.desktop.shani.service`; `data/systemd/shani-chronoa-bridge.service:4-10` | Ship `.service` files in `data/dbus/` for each owned name. |
| 10 | **Bus names/paths not documented as a stable API.** Names are strewn through bridge docstrings with no central table; no version property except portal's `version=3`. | `bridge/appmenu-registrar.py:23`, `screensaver.py:30-31`, `mpris-player.py:27-28`, `chronoa-bridge.py:50-63`, `service.py:38`, `portal.py:32`; README only shows CLI examples `README.md:332-345` | Publish one `docs/dbus-api.md` table: name / path / interface / methods / since-version. |
| 11 | **No versioning or deprecation policy on D-Bus interfaces.** Contrast the CLI/IPC version gap already filed — the *D-Bus* surface has no `SHANI_DBUS_VERSION`, no `Version` property, no ABI contract. | XML definitions in `portal.py:24-30`, `screensaver.py:36-53`, `chronoa-bridge.py:65-98`, `service.py:56-140` all lack version | Add a `Version` property (u) to each interface + a documented deprecation rule. |
| 12 | **All bridges open names with `BusNameOwnerFlags.NONE`, no queue/replace policy for graceful handover.** | `portal.py:212`, `screensaver.py:70`, `chronoa-bridge.py:415,444,446`, `shani_link/service.py:484`, `mpris-player.py:182` | Use `ALLOW_REPLACEMENT|REPLACE_EXISTING` on upgrade paths with an owner-change watch. |
| 13 | **Flatpak reachability of shell D-Bus names is undefined.** `flatperm.py` accepts `talk-name` flags and the UI exposes only that toggle; none of the shell's own names are declared/documented as needing a grant, so integrators can't know what to request. | `bridge/flatperm.py:39-40`; `docs/GAPS-RESEARCH.md:118` (ownership UI gap already filed — *this* is the missing name manifest) | Ship a `shani-shell` Flatpak permissions manifest listing each owned name. |
| 14 | **No introspection-level docs for the relay contracts.** `org.shani.Chronoa.Mascot/Windows` are described only in a bridge docstring; the tool-call pill protocol (`Cue`) has no payload schema for third parties. | `bridge/chronoa-bridge.py:4-16,100-110` | Document payloads + emit standard introspection XML (already registered at :435-437 — just publish). |
| 15 | **Portal is `FileChooser`-only as a public API** — Email/Share/Send and `org.freedesktop.FileManager1.ShowItems` are absent, so apps that target those freedesktop APIs can't integrate with the shell at all. | `data/portal/shani.portal:3` (`Interfaces=…FileChooser;`); `docs/GAPS-RESEARCH.md:96,404` (filed as feature gaps, not API surface) | Extend `shani.portal` Interfaces and implement the methods on `portal.py`. |
| 16 | **No "caller identity" exposure for compat interfaces** — `appmenu-registrar` records `sender` but only to hand menu paths back; no consumer can ask "who owns this shell action?" | `bridge/appmenu-registrar.py:33-56` | Add an `Owner` property/introspection annotation on owned menu/window objects. |

**Comparison (context, not new gaps):** GNOME Shell deliberately removed Eval but still publishes documented `org.gnome.Shell` / Shell-Extension D-Bus; KDE ships versioned `org.kde.*` interfaces with introspection; sway publishes a documented, versioned IPC socket protocol. Shani has a large *private, unversioned* `qs ipc` socket plus undocumented compat D-Bus names — closest to sway's socket in mechanism but with neither sway's protocol doc nor KDE's versioning.

**Ranking note:** #1–#6 are security (high value, low effort — mostly one `sender` check each); #7–#12 are the API-design core; #13–#16 are documentation polish.

End notes: I did not runtime-verify D-Bus sender credentials or Quickshell socket file modes (no bus/Flatpak in this container) — all security claims are static. Risk: #2/#5 may be intentional bus-wide design; confirm with the Chronoa/Link owners before hardening so legitimate peers aren't locked out.

## VERBATIM: Chronoa backend under-exposure

# Fourteenth-pass deep gap research — shani-chronoa backend under-exposure in the shell

Static only. Read both GAPS files and skipped the listed Chronoa gaps (conversation history, cloud visibility, tool-choice/selection, prompts, window context, model switch, markdown replies, translations, voice/wake/PTT controls, approvals, privacy/memory, streaming cancel, backend items 15–22, LSP/etc.). Ranked by value × ease.

## High value / low ease-to-high value (do first)

**1. Structured tool arguments are thrown away.**
Backend emits `tool` / `tool_done` with `tool` and `args` fields, not just prose (`agent_service.py:190-198`). Both shell handlers read only `e.text` (`ChronoaSurface.qml:33-36`, `Chronoa.qml:79-85`). Sketch: pass `e.tool`/`e.args` into `panel.addTool()` and render an expandable "ran <tool>(<args>)" row — the shell's tool pill currently cannot say *what* ran.

**2. Compaction events are silently dropped.**
`on_compaction` fires once per turn when history is elided (`agent_service.py:209-210`); neither `Chronoa.qml:72-105` nor `ChronoaSurface.qml:32-50` has a case. Sketch: add a dim "Earlier turns were trimmed to fit" line so "it forgot what I said" is distinguishable from a full window.

**3. Turn-id broadcasts are ignored.**
Bridge emits `{"type":"turn","id":...}` for each `Agent.Turn` reply (`chronoa-bridge.py:232-235`); `Chronoa.qml:119-149` has no `e.type === "turn"` branch. Sketch: keep the id in `Chronoa` so approvals/cards can be keyed to a turn without re-parsing prose.

**4. The shell exposes only 4 of ~36 Chronoa GActions.**
Backend registers 36 actions in `_create_actions()` (`application.py:1688-2095`); shell QML names only `toggle-listening`, `dictate`, `stop-speaking` plus the `page:` path through `Services/Chronoa.qml:51-53`. Sketch: add a bridge `op:"gaction"` allow-list (name + optional variant) and wire the high-value ones below rather than hard-coding each.

**5. Project folder / Build mode is unreachable from the shell.**
`choose-project` and `clear-project` exist (`application.py:1912-1917`) and `buildmode.set_project()` feeds skills/prompt; shell has no project control. Sketch: expose through #4 and show current project in the Island pill.

**6. MCP server state is invisible.**
Backend ships a real stdio MCP server exposing all skills (`mcp.py`); `reload-mcp` exists (`application.py:1921-1924`) but the shell cannot list configured servers or tool count. Sketch: bridge op returning `mcp-servers` setting + discovered tool count, shown in Settings > Chronoa. (Distinct from listed item 18, which is about *registering* tools.)

**7. Inbound channel bridges have no shell face.**
`gateway.py` (Registry, `Submit`, rate limits) and `channel_bridge.py` (Telegram/WhatsApp) plus `lan_bridge` are fully built; `chronoa-bridge.py:191-222` has no gateway op and `SettingsChronoa.qml:1-56` has no row. Sketch: read `gateway.Registry.names()` over D-Bus, show "Listening for: …" + a start command for the bridge, mirroring Chronoa's own Privacy row.

**8. Chronoa's entire Settings window is behind an external process launch.**
`SettingsChronoa.qml:40-48` shells out `gapplication action dev.shani.chronoa open-settings`; the schema has ~225 keys and `settings_window/` has five sections, while the shell surfaces only enable/kill + one Island toggle (`:24-43`). Sketch: expose a short list of machine-wide switches (auto-start, start-hidden, debug, ambient rules) directly in the shell page and leave deep tuning to Chronoa.

**9. Mascot settings are declared and read but have no shell control.**
`mascot-enabled`, `-corner`, `-sounds`, `-sounds-volume` are schema keys read by the app; the shell receives `Status/Show/Art` over `org.shani.Chronoa.Mascot` (`chronoa-bridge.py:4-8,50-52,327-377`) but cannot flip any of them. Sketch: add a "Desktop companion" row group under #8.

**10. Learned tool priors never reach shell suggestions.**
`learning.evaluate_bandit`, `experience_summary`, `organ_status` are computed but only displayed in Chronoa's own Learning panel; `Smart.qml:15-38` and `SmartReplies.qml:20-35` are fixed regex/instruction logic. Sketch: ask Agent for a ranked skill hint (one `Write` call) and order the clipboard chips by it. (Distinct from listed "static suggested prompts", which is about the *panel* chips.)

**11. Search provider runs on a separate bus name the shell ignores.**
Backend `search_provider.py` exports GNOME Shell SearchProvider2 / KRunner `org.kde.krunner1` independently; the shell launcher uses its own index. Sketch: expose a bridge op that forwards launcher queries to the backend provider so both surfaces rank the same corpus.

**12. Usage/cost telemetry has no shell surface.**
`usage.py` / `dashboard.py` track tokens and provider cost; the shell's Island and panel show no per-turn or per-day total. Sketch: extend the bridge `event` stream with a compact usage record and show a small footer in the panel.

## Lower value / still concrete

**13. `answer-question` action cannot be driven from the shell.** Registered at `application.py:1992-1994` for notification-originated questions; the shell's notifications module only offers `Chronoa.ask()`. Sketch: add a notification action that calls it with the answer string.

**14. `setup` / `setup-page` are only reachable by spawning the app.** Registered at `application.py:2065-2080`; shell cannot open a specific setup page (ears/voice/memory) when a model is missing. Sketch: reuse `page:` prefix in `Services/Chronoa.qml:51-53` for `setup:<tag>`.

**15. Voice-clone reference-clip health is not visible.** Backend `voice_clone.clip_problem()` reports missing/oversize recordings; shell has no row for it. Sketch: add to a voice status card fed through the bridge (avoids the listed voice-*control* gap — this is file health, not switches).

**16. Cloud speech recognition is unavailable to shell dictation.** `cloud_voice.CloudSTT` exists with its own consent switches; `bridge/dictate.py:165-213` only builds local `stt.build_stt`. Sketch: add a fallback branch when no local model is provisioned, gated on the existing `cloud-stt-enabled`.

**17. `transcribe-file` action is unreachable.** Registered at `application.py:2087-2090`; the shell's recorder saves files but cannot hand one to transcription. Sketch: add "Transcribe" to the recording card's action row via #4.

**18. `find-in-conversation` / `show-body` / rail/sidebar toggles are app-only.** Registered at `application.py:1817-1841`; the shell panel has its own transcript and no bridge to these. Sketch: map them to panel-local actions instead of D-Bus where the widget exists.

## Method risk
All conclusions are static; no QML runtime, D-Bus introspection of a live session, or backend execution was performed. Items 4–9 assume bridge actions can be dispatched generically; an allow-list is required because `ActivateAction` (`chronoa-bridge.py:296-300`) currently passes no parameters and several backend actions need string variants. Items 10–12 need new Agent events — the bridge only forwards the fixed event set in `agent_service.py:18-28`.

## VERBATIM: Niche/commercial desktop comparisons

Read all 13 passes plus the three context docs. Below are features from OSes/desktops the earlier passes never compared (elementary 8, Mint/Cinnamon, Garuda, Batocera/LibreELEC/Kodi, tvOS/Tizen/webOS, ChromeOS, Clear Linux, postmarketOS, etc.). I excluded every idea already filed in the seven earlier "other desktops" tables and the 15 "latest releases" items. All verdicts are static — no runtime, hardware or TV remote was available.

## New findings — QML shell + bridges can deliver

**1. Cinnamon-style Panel Edit Mode + applet manager (Linux Mint)**
Other: right-click panel → Applets, add/remove/reorder applets by drag, manage multiple panels. Today: bar widgets can be toggled but not reordered; one bar + one dock. Feasibility: High (bar is a Repeater; Docking profiles already persist layouts). Sketch: Settings › Bar › "Customize…" enters a drag/remove mode over bar delegates, persisting order via `Settings.data`.

**2. Taskbar-style window list in the bar (Cinnamon/webOS shelf)**
Other: every open window is a labeled button — click to focus, right-click to close, active one marked. Today: app menus, tray and dock with running dots, but no per-window buttons. Feasibility: High — `Niri.windows()` already exposes titles/ids. Sketch: a "Window list" bar applet of focus/close chips, gated for TvHome and narrow screens.

**3. App-grid Edit Mode — reorder, hide, folders (tvOS/Tizen/webOS home)**
Other: hold a tile → jiggle mode, drag to reorder, hide apps, group into folders. Today: ranked launcher + category chips; no persistent user order or hide. Feasibility: High. Sketch: a "Customize apps" toggle in Launcher → drag reorder, hide, create folder; persist an order array and hidden set.

**4. tvOS "Top Shelf" focused-app hero preview**
Other: focusing a tile swaps a large banner above the grid for that app's art plus two or three contextual actions. Today: TvHome is a flat app grid. Feasibility: High. Sketch: header delegate bound to TvHome's focused index, showing art + deep links from the app's `.desktop` `Actions=`.

**5. LibreELEC/Kodi "Continue Watching" row**
Other: home row of in-progress films/episodes with progress bars and Resume. Today: Media Player has a recent-media list and persisted resume points, but TvHome does not surface them. Feasibility: High. Sketch: TvHome section fed by `PlayQueue` resume entries, each tile with a progress bar and "Resume".

**6. Batocera/EmulationStation game library**
Other: per-system grids with box art and metadata (genre, players, rating), favorites, last played. Today: games are Flatpak-only; the gamescope console has settings tiles, no library. Feasibility: Med — scrape installed game `.desktop` files and a Steam library for art. Sketch: a Games app/TvHome section with art tiles, favorites, last-played and a launch button.

**7. Garuda Network Assistant — guided troubleshooter**
Other: a wizard walks cable/Wi-Fi → IP → DNS → gateway → internet, showing pass/fail and a Fix button per step. Today: captive-portal detection and a NetworkManager settings page, no guided diagnosis. Feasibility: Med-high (`nmcli`/`ping`/`dig` already used). Sketch: a "Fix connection" card stepping through those checks with one-click remedies.

**8. Garuda upgrade-adviser "needs attention" card**
Other: after an update, a hook lists orphaned packages, stale AUR packages and `.pacnew` files, with a critical notification. Today: Updates shows failures/history; Cassini Maintenance cleans caches; nothing flags post-update review. Feasibility: High. Sketch: after an update, a card listing unused Flatpak runtimes, outdated Flatpaks and changed config files, each with an action.

**9. Unresponsive-app watchdog — Wait / Force Quit (elementary/GNOME)**
Other: a frozen app dims and offers Wait or Force Quit. Today: no freeze detection; the window menu force-kills only the focused window. Feasibility: Med — niri exposes no freeze event, but System Monitor already polls `/proc`; map D-state/stalled pids to windows over niri IPC. Sketch: a watchdog card naming the app, with Wait / Force Quit behind the existing two-click confirm.

**10. ChromeOS clock → combined calendar + notifications tray**
Other: clicking the clock opens one panel with a month calendar, upcoming events and notifications. Today: Calendar, the notification centre and the clock are three separate surfaces. Feasibility: High. Sketch: the bar clock opens a right tray embedding the existing Agenda day list and notification cards.

**11. ChromeOS lock-screen accessibility dock**
Other: a persistent lock-screen button opens magnifier, screen reader, high contrast and captions. Today: the lock surface has camera/power/media only; `Super+Alt+S` is the sole toggle. Feasibility: High. Sketch: a small a11y chip on the lock surface applying the existing `Access.qml` toggles without unlocking.

**12. Kodi profiles on a shared TV**
Other: switch profiles; each has its own watched state, favorites and settings, PIN-gated. Today: per-user settings exist, but Media Player/TvHome hold one library state. Feasibility: Med. Sketch: an Island profile switcher with per-profile watched/favorites stores and a Keyring PIN.

**13. Clear Linux "Verify & Repair" (`swupd verify --fix`)**
Other: verify installed file integrity and repair corrupt files with one command. Today: health check and problem report are read-only — "no remediation actions" is already an open gap. Feasibility: Med — `pacman -Qkk`/Flatpak checks over the active slot, fix via polkit. Sketch: Settings › About › "Verify system files" → list of changed/missing files + Repair.

**14. Starred files virtual folder (Pantheon Files)**
Other: star a file; a "Starred" sidebar folder shows favorites across folders. Today: Files has bookmarks and tags/ratings in Photos, but no favorite files. Feasibility: High. Sketch: a star action in the file list/Quick Look plus a "Starred" sidebar entry backed by a JSON path list.

**15. External media drive → "index / play" prompt (Kodi)**
Other: inserting a drive with media offers to add it to the library. Today: removable-media defaults choose an opener, but nothing offers to index. Feasibility: Med (udisks + an ffprobe/mediainfo scan). Sketch: on mount, a card offering "Add to library", "Open in Media Player" or "Ignore this drive".

**16. Screenshot / Screen record in the power menu (ChromeOS)**
Other: the power/status menu has direct Capture and Record entries. Today: Screenshot and Screen Recorder exist as apps and capture tools have no in-place key list; the power menu only has Shut down/Restart/Suspend/Log out/Lock. Feasibility: High. Sketch: two power-menu rows invoking the existing capture services with their current settings.

## Explicitly out of scope (hardware / server / compositor)

visionOS gaze-and-pinch windows and Mac Virtual Display; SteamOS community controller-layout downloads (server) and fan curves (firmware); Tizen bezel rotation and HDMI-CEC (Batocera/LibreELEC); webOS Magic Remote pointer; postmarketOS/Mobian charging profiles, phosh orientation lock and emergency call (modem); Manjaro kernel/GPU-driver switching and NixOS generations boot entries (privileged/installer); Garuda cloud-save sync and retroachievements (server); Tizen Multi-view and true PiP (niri has no arbitrary PiP).

**Skipped / risk:** I did not verify any of these against a QML runtime, hardware or a TV remote — feasibility is inferred from existing bridges/`Niri` IPC calls, so item 9 (no compositor freeze event) is the least certain. Items 12 and 15 assume per-profile state and drive-scanning that would need a small new data store.

## VERBATIM: Shani Link GTK app features not surfaced in shell

# Fourteenth-pass gaps — shani-link GTK app features the QML shell never surfaces

Scanned `shani-link/{README.md,shani_link/app/*,shani_link/{service,settings,android,fm_radio,nfc,ir_remote,moyoung}.py}` against `shani-shell/{shani/Services/Link.qml,Phone.qml,CallsWindow.qml,MessagesWindow.qml,bridge/link.py}`. Ranked by value × ease. Static only.

**1. Five of seven GTK pages have no shell entry point — [high × trivial].** GTK has Phone, Watch, Devices, Radio, NFC, Remote, Background (`shani-link/shani_link/app/window.py:90-98`) with `--page=`/alias deep links (`:102-110`), but the shell only ever execs `--page=phone` and `--page=contacts` (`shani-shell/shani/Services/Phone.qml:41-58`; `Island.qml:51`). Watch/Radio/NFC/Remote/Background/Screen are invisible from the shell. *Sketch:* Shell launcher/menu tiles calling `shani-link-app --page=<id>`.

**2. No Link settings UI — [high × easy].** GTK's Background page exposes 14 named switches with explanations (`shani-link/shani_link/settings.py:22-37`, `app/switches.py:24-70`, `app/background.py:40-60`); the shell has zero way to view or set any of them. *Sketch:* `link.py settings [key] [on]` via D-Bus `Settings`/`SetSetting` (`service.py:49-50,350-357`) + a Link Settings panel.

**3. Screen mirroring has no shell controls — [high × medium].** GTK Screen page offers Check / Start / Share a window / Stop, an off-by-default Touch switch, a full last-action report, and names the phone-side sound/mic/camera buttons (`app/screen_share.py:78-145,161-274`). Shell has no equivalent (its Radio/Screenshot services are unrelated). *Sketch:* `link.py screen <status|start|start-window|stop>` + a tile with a Touch toggle and full report label.

**4. Watch dashboard is entirely GTK-only — [high × medium].** Steps-vs-goal ring, 3-day bars, sleep stages, stress sparkline, on-demand heart rate / SpO₂ / blood pressure, workouts, Find, Sync time, watch Settings and "Send to watch" (`app/wearables.py:617-650`; `app/watch_dashboard.py:137-372`). `bridge/link.py:42-45` imports no watch module. *Sketch:* `bridge/watch.py` over `moyoung.health_summary()/measure()/find()`; QML cards with Theme styling.

**5. Android USB tools are reduced to one "share" call — [high × medium].** GTK exposes battery/storage, screenshot, send file, list apps, paste-and-open link (`app/android.py:302-398`), but the engine also has screen recording, launch app, brightness, pull, plus notifications, screen time, telephony line, Wi-Fi, thermal, location and display reads (`shani_link/android.py:34-35,135-300`). *Sketch:* `link.py android <verb> [serial]`, show as a Devices tab.

**6. Phone diagnostics reads never reach the shell — [medium-high × easy].** D-Bus `Phone` offers `Notifications`, `Usage`, `Line`, `Wifi`, `Thermal`, `Location`, `Display` (`service.py:105-111,323-329`); `bridge/link.py` uses none. *Sketch:* seven one-line bridge commands + a "Phone" status tile.

**7. Live in-call controls missing from Calls — [high × medium].** GTK has a call timer, mute, audio-output picker, DTMF keypad, hold/swap/merge, call-status refresh, two-sided recording and a video surface (`app/phone.py:776-806,926-1026,1469-1579`). Shell `CallsWindow.qml:41-160` is a pad + history only; `Link.hangup()` is unused there. *Sketch:* `link.py callctl <action>` and an in-call card bound to `Link` state.

**8. SIP account manager has no shell surface — [medium × medium-high].** GTK add/edit/remove with UDP/TCP/TLS, preset ports, password kept server-side, Undo (`app/sip_accounts_view.py:26-120`; `sip_accounts.py:1-40`). Shell has no VoIP settings and `Link.lines` only shows landline/modem ids (`bridge/link.py:cmd_state`). *Sketch:* bridge wrapper over `app/sip_client.py` + a small settings page.

**9. Phone music control not in Media Player — [medium × easy].** GTK Music tab shows current track with Previous/Play-or-pause/Next/Refresh over MPRIS (`app/phone.py:1914-1949`). Shell's Media Player has no phone source. *Sketch:* `link.py media <action>` and a "Phone" source row.

**10. Received-files list and receive switch missing — [medium × easy].** GTK Files tab lists the 40 newest files in `Downloads()` with sizes and toggles "Receive files from your phone" in place (`app/phone.py:1950-2027`). Shell only does one-way `share()` (`Link.qml:51`). *Sketch:* `link.py received` + a Files section in Link.

**11. Shell always picks the first device — [medium × medium].** GTK keeps one card per adb serial (`app/android.py:410-490`), per watch (`app/wearables.py:617-650`), and passes device ids everywhere; shell hardcodes `_first_device()` (`bridge/link.py:88,238,251,294`) and `phone` = first paired/reachable (`Link.qml:33`). *Sketch:* add device ids to `Link.devices` and a picker used by send/dial/share.

**12. Generic BLE/GATT inspector — [low-medium × medium].** GTK shows friendly UUID names, stored values, and a 10-second `Listen` for notify-only characteristics (heart rate etc.) on every paired LE device, plus iPhone-on-USB detection (`app/wearables.py:352-415,510-593`; `app/devices.py:320-340`). *Sketch:* read-only `link.py gatt <mac>` list.

**13. Live FM/SDR radio is absent from shell Radio — [medium × medium, hardware-gated].** GTK has 14 frequency presets, Tune/Stop/Volume/Play recording/Find stations/Bands (`app/tools_pages.py:307-344`; `fm_radio.py:677-773`). Shell `Services/Radio.qml` is internet radio only. *Sketch:* thin `bridge/fm.py` + a "USB radio" section in RadioView.

**14. NFC read/write UI — [low × medium].** GTK reader detection and Read (6/15/30 s) / Write link actions with explicit empty state (`app/tools_pages.py:346-371`; `nfc.py:376-410`). Shell has no NFC surface. *Sketch:* reuse the GTK action-page shape in a QML panel.

**15. Infrared remote learn/send — [low × medium].** GTK learns a button, picks a remote/key from `irsend`'s own lists, or sends a raw NEC/RC-6 code, with send-capability gating (`app/tools_pages.py:373-435`; `ir_remote.py`). Shell has nothing. *Sketch:* `bridge/ir.py <receive|remotes|keys|send>` + panel.

**16. Pairing wizard's QR/passkey flow is unreachable from shell — [medium × easy].** GTK shows an adb Wi-Fi QR code, pairing-code entry and mDNS discovery (`app/connect_device.py:526-560`), Bluetooth confirm/passkey prompts (`:369-406`), and LAN pairing with Accept/Cancel (`:616-703`). Shell has only `kdeconnect-cli pair/unpair/ping` (`Phone.qml:21-28`). *Sketch:* one "Connect a phone" tile launching `shani-link-app --connect=android|bluetooth|kdeconnect`.

*Skipped as instructed:* Messages/Calls/Phone comparison, Link engines, device management mechanics, clipboard share, kdeconnect, PBAP/MAP, tethering. Not checked: whether bridge import of `moyoung`/`android` is safe when shani-link is absent (the existing `_module()` helper suggests yes); hardware-dependent items 13–15 are untestable in the dev container.

---

# Thirteenth pass — VERBATIM agent reports

## VERBATIM: Undo/redo consistency

# THIRTEENTH-PASS — UNDO/REDO CONSISTENCY (static, read-only)

Method: grepped all 351 QML modules + Services for `undo`/`redo`/`pushUndo`/`trash`/`remove`/`confirm`/`Key_Z`, read the undo primitives (`Common/Toast.qml`, `Services/Files.qml:836-880`, `Common/Settings.qml:72-90`, `Services/TextDocs.qml`, `Services/WindowLayouts.qml`). Skip-list items excluded (editor, Files, WindowLayouts, TextFields, Notes, RRULE, PDF history). "Undo" below means a reversible user action, not a trash backend.

## A. Destructive, single-click, zero undo (highest value × ease — reuse the existing two-tap pattern)

1. **Photos "Move to trash" bypasses the Files undo stack entirely.** `PhotosWindow.qml:418-421` → `Viewer.trash()` (`Viewer.qml:300-309`) calls `gio trash` directly and "optimistically drops it from the folder" — no `Files.pushUndo`, so no Undo bar anywhere. **Sketch:** route through `Files.trash(paths, cb)` (as `PhotosWindow.qml:92-96` already does for batch). Highest-value gap in this pass.

2. **Mail delete is one click, no confirm, no undo — hits IMAP.** `MailWindow.qml:304-307` → `Mail.remove()` (`Services/Mail.qml:47`, `126`) → server delete. **Sketch:** two-tap confirm (pattern at `ContactsWindow.qml:37-39`) before `Mail.remove`.

3. **Calendar event delete is one click, no confirm, no undo — writes EDS.** `CalendarPanel.qml:1325` → `deleteEditor()` at `:446-449` → `Agenda.deleteEvent()` (`Services/Agenda.qml:145`). **Sketch:** two-tap, or capture payload and offer "Undo" toast before the EDS write.

4. **Feed subscription "Remove" is one click, no confirm, no undo.** `FeedsWindow.qml:112-115` → `Feeds.remove()` (`Services/Feeds.qml:50`) → bridge `remove`. **Sketch:** two-tap + keep `(url,title)` for an Undo that re-adds.

5. **SSH host delete is one click, no confirm, no undo.** `TerminalAppWindow.qml:180` → `TerminalApp.deleteHost()` (`Services/TerminalApp.qml:41`) rewrites the config. **Sketch:** two-tap; Undo re-inserts the saved entry.

6. **Web-app remove is one click, no confirm, no undo.** `SettingsWebApps.qml:23-25` → `WebApps.removeApp()` (`Services/WebApps.qml:42`) deletes the .desktop + icon dir. **Sketch:** two-tap + stash the descriptor for re-add.

## B. Two-tap confirmation exists, but there is still no undo (medium value, trivial ease)

7. **Contact delete** — `ContactsWindow.qml:443-452` (4 s timer `:39`), `Contacts.qml:112`. Two taps protect against slips, not regret; no restore. **Sketch:** on delete, toast "Contact deleted · Undo" re-writing the VCF.

8. **Authenticator key remove** — `AuthenticatorWindow.qml:26,94,195-199` (4 s), `Keyring.qml:30`. Removing a TOTP secret is unrecoverable and locks the user out of a site. **Sketch:** keep the secret in memory for the toast window; Undo re-writes it.

9. **App uninstall / leftover / AppImage remove** — `SoftwareWindow.qml:35,333-335,510-512,541-542` (4 s), no undo. **Sketch:** Undo re-runs install / moves leftover back from trash.

10. **Container / image remove, box remove, and unconfirmed prune** — `ContainersWindow.qml:233-236,308-311,381-384`; `prune` at `:349-351` has **no confirm at all**. **Sketch:** two-tap prune; record `id` for a re-pull/re-create Undo.

11. **Process end — KILL has no undo** — `Processes.qml:343-415` (3 s two-tap) → `TopProcesses.qml:36-38` `kill -KILL`; no way to restore a killed process's state. **Sketch:** label "End (cannot be undone)" for KILL, prefer TERM by default.

12. **Clipboard wipe is irreversible** — `Clipboard.qml:160-166` `wipe()` blanks primary + history in one call, no confirm/undo. **Sketch:** move entries to a one-deep "recently wiped" stash exposed as Undo.

13. **Notification "Clear"/"Clear all"** — `Notifs.qml:179-182` dismisses every tracked notification, no undo (also `NotificationCard.qml:129` Delete key). **Sketch:** keep dismissed ids in a toast-undo list and re-announce.

14. **Automation rule removal/toggle writes immediately** — `SettingsAutomations.qml:60-62` (`setRules`) and `:59`. No confirm, no undo, and a removed rule's text is gone. **Sketch:** stash the previous rules array; Undo restores it.

## C. Multi-step operations — batch is atomic in one place, not elsewhere

15. **Folder sync (`rsync`) has no undo** — `Services/Files.qml:1295-1309` writes "Folders synced" with no `pushUndo`, unlike copy/move at `:664-670`. A sync can overwrite many files. **Sketch:** preview + `--backup-dir` and push one inverse undo entry.

16. **PDF merge has no undo** — `PdfReader.qml:36-41` → `PdfViewer.merge()`; result is a new file with no removal/undo path. **Sketch:** Undo = trash the output, keep source list.

17. **Video trimmer segments have no undo** — `Services/VideoTrimmer.qml:198-224` `addSegment/removeSegment/clearSegments` mutate an array with no history; `S` split and `clearSegments()` (`:209`) wipe multi-segment work in one key. **Sketch:** one `undo` restoring the previous `segments` array; add `Ctrl+Z` in `VideoTrimmerPanel.qml:29-34`.

18. **Settings "Undo" is not a true undo** — `Common/Settings.qml:72-90`: `undo(key)`/`undoAll()` reset to the **sign-in snapshot** (`loadedValues`, taken at `onLoadedChanged:47`), so A→B→C undoes straight to A, not B, and after a shell restart the snapshot *is* C so Undo silently vanishes. UI is a rail button only (`SettingsWindow.qml:178,185`), no `Ctrl+Z`. **Sketch:** push per-change old values onto a small stack; persist or document "back to sign-in".

## D. Cross-cutting (systemic, never audited as a discipline)

19. **Undo affordances are inconsistent and mostly unreachable.** Undo keybindings: Files `Ctrl+Z`/`Ctrl+Shift+Z`/`Ctrl+Y` (`FilesPanel.qml:142-148`); TextEditor full (`TextEditorPanel.qml:435-436`); Whiteboard `Ctrl+Z` **no redo** (`Whiteboard.qml:120`); Annotate **bare `Z`** and bare `E` clear that is unrecoverable (`Annotate.qml:92-94`); WindowLayouts undo-only; Settings button-only; most destructive apps **no shortcut at all**. The 2-tap windows use three different timers (3 s `Processes.qml:344`, 4 s Contacts/Authenticator/Software/Disks, 7 s Files note `:2893`). **Sketch:** one shared "last destructive action" Undo action bound to `Ctrl+Z` + a single confirm-timer helper.

20. **Toast Undo is fragile and inaccessible.** `Common/Toast.qml` is the *only* QML with `Qt.accessibleAnnounce` (`:29`), auto-dismisses in **5 s** (`:67`), and its Undo `Button` (`:57-63`) has no KeyFocus/shortcut — unusable by keyboard or screen reader. Files' much more common undo bar (`FilesPanel.qml:2872-2894`) has **no announce and no Accessible name**, lasts **7 s** (`:2893`), lives inside the Files window, so an undo triggered from another app has no visible surface (cross-app undo cannot be surfaced), and none of it survives a shell restart (all undo stacks are in-memory properties: `Files.qml:837`, `Settings.qml:44`, `WindowLayouts.qml:42`). **Sketch:** give Undo buttons `KeyFocus`/`Accessible.name`, unify duration to ~10 s, and rehome the bar in a shell-level layer so any app's undo can be shown.

**Skipped:** no runtime verification (static only); did not re-audit the seven listed items or re-test the prior research items I extended (only added consistency framing). **Risk:** #1 is a one-line call-site change but must confirm `Files.trash` callback refreshes Photos' own `list` — `Viewer.trash` currently mutates it directly at `:305-309`.

## VERBATIM: External service integrations

# 13th-pass audit — external service integrations & webhook/API surface (read-only, static)

**Skipped (already in GAPS files):** webhook server (Chronoa's WhatsApp HMAC adapter), no log upload, shani-insights, remote desktop, IFTTT-style automation actions, CalDAV accounts, missing CardDAV, rclone mounts, GOA/Online Accounts, portal Notification/Email/Share, share-sheet→own-apps, shani-link SMS/calls.

**What exists (so the gaps are precise):** inbound notifications come only from the shell being a standard `org.freedesktop.Notifications` daemon (`shani/Services/Notifs.qml:1-2`; `notify-send`/`gdbus` work, `docs/voltkit-alignment.md:33`). The only HTTP listener in the tree is a folder share (`bridge/serve.py:1-16,32-34,218-223`); the only true webhook is in shani-chronoa (`usr/lib/shani-chronoa/shani_chronoa/channel_bridge.py:209-266`, feeds `Submit` D-Bus — Telegram/WhatsApp only, `ARCHITECTURE-TARGET.md:471`). Outward: `Services/Automations.qml:6-11,32-53` = 5 triggers / 6 actions (`run` is `sh -c`); `Services/Hooks.qml:3-5,17-19` = 6 local events. `bridge/cloud.py:2-18,29-37` mounts rclone drives only. No MQTT/Home Assistant/GitHub/GitLab/Slack/Discord/Matrix reference exists anywhere in shani-shell.

### Shell-fixable — ranked by value × ease

1. **[high × trivial] No `shani notify TITLE BODY`.** `bin/shani:34-384` defines 39 command groups, none `notify`; a script/cron/phone must know raw `gdbus`/`notify-send` (`README.md:378` shows it only as a harness tool). *Sketch:* add a `notify` group that calls the D-Bus `Notify` method with `--urgency/--app/--hint`, and document it as the phone→desktop push path.
2. **[high × med] No authenticated inbound webhook.** `bridge/serve.py` serves GET/PUT files only; nothing maps an HTTP POST to a notification. *Sketch:* `bridge/webhook.py` loopback/LAN endpoint, per-token HMAC (mirror Chronoa's `channel_bridge.py:249-266`), JSON→D-Bus `Notify`; bind loopback by default and document a tunnel for remote callers.
3. **[med × easy] No remote ICS calendar subscription.** `bridge/agenda.py:11-13,602` only imports a local `.ics` or adds a CalDAV account (`agenda.py:551-582`). *Sketch:* `agenda.py subscribe URL` polls a read-only ICS into a local EDS calendar — covers team-leave and ticket-milestone feeds.
4. **[med × med] Mail never pushes a new-message alert.** `bridge/mail.py:376-404` opens IMAP on demand with no `IDLE`; `Services/Mail.qml:43,158` refreshes only on open/action. *Sketch:* a small IMAP `IDLE` watcher in `mail.py` emitting one notification per new message (reuse #1).
5. **[med × med] Share can't upload to a cloud or POST a file.** `Services/Share.qml:20-35` offers phone/BT/LocalSend/QR/email/copy/open; `bridge/cloud.py` has `add/mount/remove` but no upload or link command. *Sketch:* `cloud.py upload NAME FILE` and `link NAME FILE` (rclone `copyto`/`link`) plus two Share targets.
6. **[med × med] No machine-readable shell event stream.** Battery-low exists but only calls `notify-send` (`Services/Power.qml:97-113,120-130`); hooks are 6 closed local events (`Hooks.qml:17-19`), automations 5 internal triggers. *Sketch:* emit a D-Bus signal/JSON-lines feed for notification, battery, download-complete and calendar-start that external daemons can subscribe to — distinct from adding more IFTTT actions.
7. **[med × med] No generic secret/token home for integrations.** Mail password is env/keyring (`bridge/mail.py:17`); rclone tokens live in `rclone.conf` (`bridge/cloud.py:112-114`); no third-party token store. *Sketch:* a `bridge/tokens.py` front end to GNOME Secret Service so webhooks/services never keep bearer tokens in plain settings.
8. **[low × easy] Feeds can't accept push.** `bridge/feeds.py:140-148` fetches by polling; no WebSub (`GAPS.md:333-338` documents one refresh timer). *Sketch:* on feed add, send a WebSub subscribe carrying the #2 webhook URL as callback.

### Needs a service / account

9. **[high × med] No Home Assistant / MQTT at all.** No `mqtt`, `hassio`, presence or sensor reference in the tree. *Sketch:* `bridge/mqtt.py` subscribes `home/presence`, `home/sensors/#` → notifications/Island card and publishes shell events (#6) back — needs a broker/HA instance and credentials.
10. **[high × med] No GitHub/GitLab integration.** `bridge/appstore.py:260-262` is HTTP only for Flathub; nothing reads notifications/PR reviews/issues. *Sketch:* `bridge/devcloud.py` polls the REST notification endpoint → Notifs, plus "issues due today" as an #3 subscription; needs a token.
11. **[high × med] No CI status surface.** Updates/Software are OS-only; no Actions/GitLab CI reader. *Sketch:* poll a repo's latest workflow run into a bar chip + Island card + notification on failure; token needed.
12. **[high × med] Messaging bridges cover only Telegram/WhatsApp.** Chronoa's `channel_bridge.py` (and `ARCHITECTURE-TARGET.md:471`) has exactly those two adapters; `Services/Phone.qml:41-59` is SMS/calls. *Sketch:* add Matrix/Slack/Discord adapters behind the same Chronoa `Submit` D-Bus — needs a homeserver/bot token per service.
13. **[med × easy] No ntfy/Gotify/Pushover subscriber.** *Sketch:* `bridge/push.py` long-polls an ntfy topic and calls #1 — the practical inbound path when the desktop has no public port; needs an account/topic.
14. **[med × med] Mail OAuth2 for Gmail/Outlook.** `bridge/mail.py:17` only reads a password from env/secret service. *Sketch:* add an XOAUTH2 bearer flow using #7; needs provider registration.
15. **[med × med] No public HTTPS endpoint for external callers.** `bridge/serve.py:218-223` binds `0.0.0.0:53318` on plain HTTP with a URL token; Tailscale is only a VPN list entry (`GAPS.md:259`). *Sketch:* document/ship a Tailscale or tunnel-based receive mode — or prefer the outbound-poll model of #13.
16. **[med × med] Cloud share links need an account to be real.** `bridge/cloud.py:29-37` supports Drive/OneDrive/Dropbox/Box/pCloud/Yandex/WebDAV FUSE mounts, but no per-file link or selective-sync/conflict UI. *Sketch:* after #5, add `cloud.py status` showing queued conflicts; needs the drive authorized.
17. **[low × med] No cross-device clipboard/URL push bridge.** Clipboard is local (`Clipboard.qml`); the GAPS research already notes opt-in phone clipboard push as a risk. *Sketch:* reuse #2/#13 with confirm + 45 s clear; needs a paired endpoint.

**Risk to flag:** #2 and #9 turn external input into shell action; ship HMAC/auth and loopback binding first (#2, #7), and keep #6 read-only, or an open webhook becomes unauthenticated `sh -c` execution via Hooks/Automations.

**Not checked:** no runtime, network, real broker/account, or QML session was available; all lines are static. I did not re-audit the explicitly noted items above.

## VERBATIM: Macro/scripting automation depth

## User-defined macros & scripting — 13th-pass gap research (read-only)

All paths below are relative to `shani-shell/`. Context docs read first; I skipped every item already in GAPS/GAPS-RESEARCH (five systems, basic vocab, templates/import-export, dry-run, unpermissioned hooks, phrase-only routines, no variables/if-else/wait/subroutines).

**What actually exists.** Three authoring surfaces, all producing raw `sh -c` strings stored inline in `settings.json`: rule engine (`shani/Services/Automations.qml:43-55`), 5 hook text fields (`shani/Modules/Settings/SettingsAutomations.qml:76-92`), key→command binds written into niri KDL (`shani/Services/InputConfig.qml:145-147`), plus a hidden Nautilus-scripts loader (`shani/Services/Files.qml:898-908`, `bridge/files.py:1983-2003`). Execution is `execDetached` fire-and-forget. No recorder, no runtime language, no event object, no visual builder.

### Ranked gaps (value × ease)

1. **No macro recorder/replay** (H×M): nothing logs ipc calls/keystrokes; `shani/Services/Clipboard.qml:116-123,147` can *type* via `wtype`, `shani/shell.qml:258+` exposes ~100 callable IPC functions, but none records. Sketch: `ipc macroStart/macroStop/macroPlay <file>` logging calls to JSONL.
2. **No named/addressable macro** (H×H): binds (`SettingsShortcuts.qml:167`) and rules (`Automations.qml:43`) store anonymous commands; nothing can invoke them except the physical key. Sketch: give each a slug + `qs ipc call shani run <slug>`.
3. **Hook event object is empty and inconsistent** (H×H): only wallpaper gets args (`Hooks.qml:37-38`), and `$2` screen name is always `""` (`Hooks.qml:87`); dark/color use string-replace `$1` (`:45,64`); lock/unlock/startup get no context (`:49-72`). No window id, app, notification body, file. Sketch: documented `SHANI_EVENT` JSON on stdin/env + `$SHANI_WINDOW`.
4. **No scripting language/SDK** (H×M): the ~29 `.js` files (e.g. `Modules/Launcher/Fuzzy.js`, `Modules/Settings/NiriBinds.js`) are static QML imports; no runtime JS/Lua/Python loader. Sketch: sandboxed runner exposing a `shani` module (state/notify/set/clipboard).
5. **No GUI macro builder** (M-H×M): authoring is only text fields/chips (`SettingsAutomations.qml:87-90,258-264`, `SettingsShortcuts.qml:155-160`). Sketch: block editor emitting the existing `{when,is,then,arg}` JSON.
6. **Rich shell state has no documented script API** (H×M): `shell.qml:998,1056-1064,1154` `state()` returns focus/media/notifs/wallpaper but as a volatile test dump with no schema/version. Sketch: publish versioned `shani state --json` + `shani get <field>`.
7. **`colorGeneration` hook orphaned from GUI** (L-M×trivial): declared `shani/Common/Settings.qml:261`, fired `Hooks.qml:61-66`, but missing from the 5-row model at `SettingsAutomations.qml:77-79` — hand-edit only. Sketch: add the sixth row.
8. **Nautilus Scripts surface is hidden and undocumented** (M×H): exec-bit scripts in `~/.local/share/nautilus/scripts` get `NAUTILUS_SCRIPT_*` env (`files.py:1983-2003`, `Files.qml:904-906`) — the only true "event object" — but no GUI to install/list/bind them. Sketch: surface in Settings > Automations, allow key/rule binding.
9. **`execDetached` prevents sequencing** (H×M): `Hooks.qml:27`, `Automations.qml:51` return no PID/exit/stdout; `shani/Common/Proc.qml:41,79` already has timeout/debounce. Sketch: synchronous macro step returning exit+stdout.
10. **No shell-state write contract** (M×H): `setting` IPC exists (`dev/shell-parts/hooks-sticky.sh:7,21` uses `ipc setting darkMode false`) but is undocumented, so scripts poke `settings.json` directly. Sketch: document a `shani set <key> <value>` command.
11. **No IPC discovery** (M×H): `shell.qml:258+` has dozens of functions, no `ipc list`; only typed signatures live in `docs/FINDINGS.md:36`. Sketch: `ipc list` returning names+arg types.
12. **IPC arg-splitting breaks structured macro data** (M×M): `qs ipc` splits JSON/list args (`docs/FINDINGS.md:1171`, `docs/GAPS-RESEARCH.md:862`, `shell.qml:901`). Sketch: `--json`/base64 arg convention for macros.
13. **Hook cascade unbounded across systems** (M×H): a dark-mode hook can change wallpaper (`hooks-sticky.sh:11`) firing the wallpaper hook; only rules have an edge guard (`Automations.qml:24,56-65`). Sketch: shared reentrancy token for hooks+rules.
14. **Scheduler is rule-only and daily-minute** (M×M): `Automations.qml:86-105` is the single clock; hooks/binds cannot be scheduled; no interval/relative/cron/`at`. Sketch: shared scheduler targeting any named macro.
15. **Inline scripts, no file-backed hook directory** (M×H): bodies live in JSON (`Common/Settings.qml:261,459`) vs Nautilus' directory model (`files.py:1983`). Sketch: discover `~/.config/shani/hooks/*.sh`.
16. **No keystroke/click replay action** (H×M): `Clipboard.qml:116-123` types text only; no key-combo or mouse action exists. Sketch: `ipc sendKeys <seq>` / `click <x> <y>` via `wtype`/`ydotool`.
17. **No macro test format** (L×H): `hooks-sticky.sh:6-23` mutates settings.json for one ad-hoc hook run; no persisted fixtures. Sketch: `shani macro test <file>` asserting payload+effects.

**Skipped / risk:** read-only — no files edited; I did not run the shell or verify the `wtype`/`ydotool` availability these sketches assume. Biggest caveat: any recorder or script SDK widens the already-unpermissioned `sh -c` path, so items 9/13 (sequencing + reentrancy) should land before 1/16.

## VERBATIM: Default apps / associations

# Default apps / file-association coverage audit (13th pass)

**Scope:** `shani-shell/shani/Modules/Settings/SettingsDefaultApps.qml`, `bin/shani` `APPS` (lines 425–588), the four desktop `skel/.config/mimeapps.list` files, `shani-install-media/iso_profiles/shared/airootfs/.../mimeapps.list`, portal/share launch paths. Static only; skipped all twelve previously listed items. Authoritative image file = `shani-pkgbuilds/shani-desktop-niri/etc/skel/.config/mimeapps.list` (per GAPS-RESEARCH:742).

**Direct answers:** (1) 25 claimed MIME types have no default; no default names an app that doesn't claim its type except `text/csv`. (2) Common types with no default: `text/vcard`, `application/ics`, `application/x-yaml|toml|css|javascript|x-desktop`, `message/rfc822`, OPML/m3u/xspf, `application/vnd.rar`, `application/x-bzip2-compressed-tar`, `application/x-eps`, `application/x-cb7|x-cbt`, `application/x-fictionbook+xml`, `application/vnd.ms-xpsdocument`, `text/directory`, `x-content/*`. (3) Text Editor/Image Viewer/Media Player/Document Viewer/Archives **are** defaults for their core types; **Photos, Feeds, Mail, Calendar, Contacts, Fonts are not** (Photos/Feeds/Mail claim zero MIME types). (4) No — writes are per-user and partial; `xdg-open` paths use a resolver the shell itself calls unreliable. (5) Per-user only, no reset, no "remember for this type" in Open-with pickers. (6) Settings exposes 8+6 kinds vs KDE's full per-MIME File Associations and GNOME's Default Apps + per-file Open With.

## Ranked gaps

1. **[high×easy] 25 types our apps claim but no default exists.** `bin/shani:427-433,441-445,478-488,514-515,550-551,563-565` vs skel: no lines. Includes `application/ics` (Calendar claims it; skel sets only `text/calendar`, `x-vcalendar`, `x-extension-ics` at :43-45), `text/vcard`/`text/directory` (Contacts at :514-515; skel's Contacts section :48-51 is empty), `application/x-yaml`/`toml`/`css`/`javascript`/`x-desktop`/`x-qml`/`x-log`/`x-readme`/`x-c++src`/`x-script.python` (Text Editor), `application/vnd.rar`/`vnd.debian.binary-package`/`x-bzip2-compressed-tar`/`java-archive` (Archives), `x-eps`/`image/x-eps`/`x-cb7`/`x-cbt`/`x-fictionbook+xml`/`vnd.ms-xpsdocument` (Viewer). Sketch: generate default lines from `APPS` mimes, not by hand.
2. **[high×easy] `text/csv` default is OnlyOffice, not our Text Editor.** skel:341; Text Editor claims it (`bin/shani:427`). A plain CSV opens the OnlyOffice Flatpak while every other text type opens our editor. Sketch: change one line to `dev.shani.TextEditor.desktop`.
3. **[high×easy] Changing a default in Settings updates only 1–4 of the type's siblings.** `SettingsDefaultApps.qml:22-30,79` writes 1 text type of 34, 4 images of 28, 3 video of 125, 3 audio of 125, 1 PDF of 18; skel sets 22/28/~70/~80/11 respectively. Every untouched sibling keeps the old app. (Browser subset already filed; this is every other row.) Sketch: expand each `kind.types` from the skel's default keys for that app.
4. **[high×easy] Settings `refresh()` reads only `types[0]`.** `SettingsDefaultApps.qml:56` queries the first type but `:97,138` display that as the row's value, so a split (or an external tool changing one sibling) is invisible; selecting a new app makes *all* rows look correct. Sketch: query/compare every type in `kind.types`.
5. **[high×med] Settings changes may not reach the shell's own `xdg-open` paths.** `shell.qml:613`, `Files.qml:394,1092-1095`, `DesktopIcons.qml:126,288,310`, `Screenshots.qml:136`, `VoiceRecorder.qml:309`, `VideoTrimmer.qml:412` call `xdg-open`/`Qt.openUrlExternally`; `SettingsDefaultApps.qml:4-5` records that xdg-mime 1.2.1 "reads mimeapps.list and then answers from the system's defaults anyway" and exits 0 on write failure. Sketch: route file opens through `Launch`/`gio open` (as Viewer does at `Viewer.qml:291-299`) or fix the xdg-utils wrapper.
6. **[high×med] No reset, no system-level default, no CLI.** Only `SettingsDefaultApps.qml:79` writes anything (`gio mime` → `~/.config/mimeapps.list`); no `/etc/xdg/mimeapps.list` or `/usr/share/applications/mimeapps.list` ships, skel is copied only at account creation, and `bin/shani` has no default-app group. Existing users can never restore image defaults, and agents cannot change them. Sketch: ship system defaults in `/usr/share/applications/mimeapps.list` + `shani default-app get|set|reset`.
7. **[high×easy] Settings has no row for most association types.** Only 8 `kinds` + 6 `mediaKinds` (`SettingsDefaultApps.qml:21-40`): no Archives, Contacts, Calendar, e-book, font, torrent, OPML/playlist, Office or URL-scheme (`magnet`, `tel`) row, so the skel's 72 OnlyOffice/19 Vivaldi/3 torrent defaults are unchangeable in the UI. KDE exposes every MIME with add/remove/reorder; GNOME has per-file Open With. Sketch: generate rows from the default MIME set instead of a fixed array.
8. **[med×easy] Six removable-media rows are dead UI.** `SettingsDefaultApps.qml:33-40` queries `x-content/*`; none of the four skels sets any `x-content/*` default and no `APPS` entry claims those types. Rows will read "No app installed for this". Sketch: hide them unless a candidate exists, or register gvfs/autorun handlers.
9. **[med×easy] ISO skel points media to apps that are not installed.** `shani-install-media/iso_profiles/shared/airootfs/etc/skel/.config/mimeapps.list:1-45` defaults audio to `io.bassi.Amberol`, video to `io.github.celluloid_player.Celluloid`; neither appears in any profile's package/Flatpak list (repo-wide grep), and the built live user's file is identical (`cache/temp/niri/x86_64/airootfs/home/shani/.config/mimeapps.list`). Sketch: replace with `dev.shani.MediaPlayer` or drop the file.
10. **[med×easy] Only the niri skel is validated.** `shani-shell/tests/test_packaging.py:95-128` hardcodes `shani-desktop-niri`; the GNOME, COSMIC, Plasma and ISO skel files have no equivalent check that their defaults name installed apps and that our apps declare what they're defaulted for. Sketch: loop over all `shani-desktop-*/etc/skel` + ISO skel.
11. **[med×easy] Photos is not an image handler.** `bin/shani:530-531` claims zero MIME types, so it never appears in `gio mime image/png` candidates or the Settings "Pictures" list; opening a photo cannot reach Photos. Same for Feeds (`bin/shani:526-527`) with OPML and Mail (`bin/shani:528-529`) with `message/rfc822`. Sketch: register `image/*` variants on Photos, `text/x-opml` on Feeds, `message/rfc822` on Mail, and add defaults.
12. **[med×easy] Playlists have no handler or default on niri.** `bin/shani:451-452` explicitly excludes `.m3u/.pls/.xspf`; niri skel has no playlist lines, while GNOME/COSMIC/Plasma skels assign them to their players. Sketch: add playlist MIME types to Media Player (QtMultimedia/FFmpeg can read them) or map to the chosen player.
13. **[med×easy] `application/x-desktop` has no default despite Text Editor claiming it** (`bin/shani:431`, skel absent). `.desktop` files open nowhere from Files/desktop icons. Sketch: one line.
14. **[med×med] No-per-type "Open with" persistence.** `Ui.qml:248-253`, `Viewer.qml:291-299`, `Files.qml:397` use `gio launch` on a chosen desktop id without writing `Default Applications` or an "only this type" preference; GNOME/KDE offer "Set as default"/"Remember for this type". (Adjacent to the already-listed "open-with can't set default".) Sketch: add a "use always for <type>" action calling `SettingsDefaultApps.choose`.
15. **[low×easy] Stale torrent comment.** skel:87 says "Default: Fragments" but :91-93 set qBittorrent; qBittorrent is native (`shani-desktop-niri/PKGBUILD:77-79`), so behaviour is fine — the comment misleads the next auditor. Sketch: fix the comment.
16. **[low×easy] `choose()` has no failure feedback.** `SettingsDefaultApps.qml:77-82` refreshes on `onExited` whether `gio mime` succeeded or not; a failed write leaves the row silently unchanged. Sketch: check exit status and show an error.

**Skipped / not checked:** runtime verification of `gio mime` vs `xdg-open` resolution (static only), and whether Flatpak-exported candidate ids resolve in Quickshell's `DesktopEntries`. **Risk to flag:** fix #3/#5 together — expanding the type lists without fixing the `xdg-open` resolver would make Settings more correct while some launch paths still open the old app.

## VERBATIM: Offline-first per app

Research complete. Both gap docs read (1885 + 1283 lines); skipped the listed cross-cutting items. All findings static, from source at the current tree.

## Per-app offline matrix

| App | Cached data that survives offline | UI when offline | Queued writes? | Edit offline? | Offline badge? |
|---|---|---|---|---|---|
| **Weather** | Only saved places (`weather-places.json`, Weather.qml:22-34). Forecast/hourly are memory-only (:114-130). | Stale in-memory values with no age; cold start → "Getting the weather… / It needs the internet" (WeatherWindow.qml:141-148). | n/a (places saved locally) | Places yes; forecast no | None |
| **Feeds** | Subs + article bodies + read/saved/tags in `~/.cache/shani-shell/feeds.json` (feeds.py:51-52; Services/Feeds.qml:1-6). | Full cached reader; generic "could not answer" note on refresh, never blank. | Local marks/tags apply at once (no server) | Yes | None |
| **Mail** | Account config only (`mail.json`:53); **no message store**. | Cold offline → "No mail yet"/"Nothing in this folder" (MailWindow.qml:103,148); failure note 5 s. | **None** — compose clears on Send (MailWindow.qml:365-374) | Compose works, send silently fails | None |
| **Maps** | Downloaded tiles in `~/.cache/shani-shell/map-tiles`, saved places (MapsPanel.qml:21,204-228). | Cached tiles render; uncovered areas blank grid, no message; "Directions failed — check the network" (:242). | Saved places local | Yes (pin/save/share) | None |
| **Translate** | n/a — local model only. | "The local model is not running" (:109); needs no internet. | n/a | Yes | n/a |
| **Software** | Flathub AppStream index in `~/.cache/shani-shell/appstore-index.json` (appstore.py:23,202-214). | Browse/search/installed work offline; ODRS ratings become 0 (:256-268). Installs need net. | Job restarts only manually | Local ops yes | None |
| **Models** | `ollama list` output only in memory; "available" list hardcoded (Models.qml:17-25,49-75). | "No models installed" whether ollama is missing or none downloaded (:133-138). | Download is detached `ollama pull`, no retry | n/a | None |
| **AIProviders/Chronoa** | Keys in keyring + dconf; transcript in memory only (Chronoa.qml:35-49). | "Chronoa is offline" = **local daemon down**, not network (Island.qml:82). | **None** — offline ask logs to transcript and is lost | n/a | **Only app with a badge** |
| **Photos** | Entirely local scan + exiv2 (PhotoMeta.qml). No geotag/GPS read. | Works offline. | Local edits only | Yes | n/a |
| **Camera** | Files on disk; gallery rescans local (Camera.qml:44-55). | Works offline. | n/a | Yes | n/a |
| **Nearby** | LAN-only; devices/known in memory (Nearby.qml:22-25). | No devices silently; firewall error if port blocked (:62). | Transfers need live LAN | Local selection yes | None |
| **VoiceRecorder** | Recordings on disk (VoiceRecorder.qml:207-253). | Works offline. | n/a | Yes | n/a |
| **Radio** | Favourites (Settings) + 50 hardcoded featured stations (Radio.qml:21-76). | Popular/Near/Genre/Search failure → **list wiped to []** and "No stations found" (:104-106, RadioView.qml:44-47). | Favourites local | Yes | None |
| **LiveTV** | Source URL persists; **channels never cached** (LiveTv.qml:16,38-71). | Cold open "No channels yet"; error wipes list (:63-69); local M3U works. | n/a | Load local file yes | None |
| **Calendar/CalDAV** | Events in memory from EDS; no shell cache (Agenda.qml:21,193-205). EDS holds CalDAV locally. | Keeps stale events, sets `available=false`; no message. | Writes go to EDS; on failure a natural-language "ask" to Chronoa, else "change not saved" (:211-218) | Yes via EDS | None |
| **Contacts** | vCard files on disk (Contacts.qml:1-7). | Works offline. | Local writer queue (:88-98) | Yes | n/a |
| **Backup** | Local snapshots (Backup.qml:62-105). | "The backup drive is not connected" (:97). | n/a | Yes | n/a |
| **Updates** | Only firmware-told list (Updates.qml:29-36); no last-checked status. | Failed check → `known=false` → **empty summary** (:62,89-98). | n/a | n/a | None |
| **shani-link** | GSConnect `sms.json` threads, contacts cache, call log, last battery (phone.py:39-41,286-299; devices.py:22). | Cached threads/contacts readable; offline device icon (devices.py:334). | **No send queue** (Link.qml:47) | Read yes | Per-device icon only |

## Ranked gaps (value × ease)

1. **Mail loses offline mail entirely** — no message cache (mail.py:53) and compose clears on Send (MailWindow.qml:365-374). Sketch: persist last N message bodies and an outbox json; flush on `Net.online`.
2. **Weather goes blank on cold offline start** — only places persisted (Weather.qml:22-34), forecast memory-only (:114-130). Sketch: FileView last forecast + render it with a freshness line.
3. **Radio wipes its list on any fetch error** — `r=[]` on parse failure (Radio.qml:104-106). Sketch: keep last-good stations per view in a cache; show them with "reconnect to refresh" instead of empty.
4. **LiveTV re-fetches the same playlist every open** — saved source not auto-loaded, no channel cache (LiveTv.qml:16,45-55). Sketch: cache parsed channels keyed by source + load saved source at startup.
5. **Calendar writes can vanish** — EDS failure falls through to a Chronoa "ask", then only a toast (Agenda.qml:211-218). Sketch: queue failed payloads to statePath and replay when `available` flips true.
6. **Chronoa prompts are dropped offline** — `deliver()` logs a message and returns (Chronoa.qml:45-49). Sketch: outbox unsent prompts; replay on `Bridge.connected`.
7. **shani-link texts dropped when device unreachable** — `send()` fire-and-forget (Link.qml:47). Sketch: outbox under `~/.cache/shani-link`, retry when device becomes reachable.
8. **Models can't distinguish "ollama missing" from "none installed"** — `|| echo '[]'` (Models.qml:51). Sketch: probe command -v and show "Install ollama…" instead of empty state (:133-138).
9. **Software ratings lie offline** — ODRS returns `[]` on any error (appstore.py:256-268), UI shows 0 stars. Sketch: return `null` and render "Ratings unavailable offline".
10. **Updates check failure is indistinguishable from up-to-date** — `known=false` yields blank summary (Updates.qml:62,89-98). Sketch: persist last-good status and show "Could not check (offline)".
11. **Maps retries failed tiles with no backoff** — `delete asked[forFile]` re-spawns curl on every pan (MapsPanel.qml:217-224). Sketch: exponential backoff per key while `!Net.online`; show cached-only hint over blank tiles.
12. **Nearby send with no devices is a silent no-op** — `sendTo()` only checks `pending` (Nearby.qml:33). Sketch: note "No devices found — check the network" after a failed scan.
13. **Feeds shows no cache age** — `fetched` is stored but unread in UI (FeedsWindow.qml:186+). Sketch: render "as of …" beside the feed title.
14. **Chronoa/Translate have no offline dictionary fallback** when the local model is down (TranslateWindow.qml:109). Sketch: ship a tiny wordnet lookup for common strings.

Already good: Feeds (cache-first reader), Contacts/Photos/Camera/VoiceRecorder/Backup (fully local), Software browsing (AppStream cache), shani-link (cached threads).

Skipped: didn't verify any behavior in a QML runtime or with a blackholed network — all verdicts are static, so "blank offline" is inferred from code paths. Risk: EDS may cache CalDAV more aggressively than the shell's own code implies; item 5's fallback path may be rarer than it looks.

## VERBATIM: Inclusive design depth

I've read both docs (12 passes) and traced the relevant QML. Skipping all listed items plus the terminological/error-tone findings already logged in the Eighth-pass "UX consistency and tone" report (trash icons, Log out/Sign out, raw bridge errors, "Click again/Tap again", empty-state grammar, success-channel rule). Below are **16 new** inclusive-design gaps, ranked by value × ease.

## Thirteenth-pass research — inclusive design (colors, icons, labels, tone)

**1. An Undo-capable Toast exists — and is used in exactly one window.** `Common/Toast.qml:3-5,34-40` has `showUndo`/`undoValue`/`undo` built in, but only `Modules/Settings/SettingsWindow.qml:259-266` ever instantiates it. Every destructive app action goes silent: `Modules/Mail/MailWindow.qml:304` (`Delete`), `Modules/Files/FilesPanel.qml:2202` (`Delete` — permanent), `Modules/Camera/CameraPanel.qml:187`, `Modules/VoiceRecorder/VoiceRecorderPanel.qml:132`. Sketch: put one Toast in `AppWindow`, fire `showToast("Deleted — Undo", true)` from those call sites. Highest value/ease: the component is already written.

**2. Destructive icon buttons are visually identical to benign ones.** `Common/IconButton.qml:32-42` has danger-free fill/icon color (`Theme.text`) and no `danger` property; `Button.qml:9,28,71` does. So `Weather/WeatherWindow.qml:133` (remove location, no confirm), `Camera/CameraPanel.qml:187` (delete capture), `Terminal/TerminalAppWindow.qml:180,475` (delete host/snippet) all look like `view-refresh`. Sketch: add `danger` bool → red icon + two-tap confirm.

**3. Two equally destructive disk operations signal different severity.** `Disks/DisksWindow.qml:429` "Erase…" is `kind:"danger"` (red), `:430` "Format…" is `kind:"outline"` (neutral) — both wipe the filesystem. Sketch: make Format `danger` too, or one shared "This erases everything on the drive" confirm.

**4. Calendar identity is color-only.** `Calendar/CalendarPanel.qml:1035` prefixes every calendar name with the same "●" glyph; the only differentiator is `Agenda.colorOf()`'s color (`Services/Agenda.qml:40`). `Accessible.name` on `:1036` omits the color. Sketch: add a distinct letter/pattern or speak the color name.

**5. SMART attributes are a raw mono dump.** `Disks/DisksWindow.qml:534-536`: nine-pixel monospace rows `ID · name · value · worst · threshold · raw`, all `Theme.faint` — no plain-language pass/warn, no meaning. Sketch: summarize "All 15 attributes normal" with the table behind a "Raw values" disclosure.

**6. Tooltips leak kernel internals into user-facing text.** `Processes/Processes.qml:444` "CPU is % since the last sample (/proc/stat deltas)", `:453` "…Disk is total read + write from /proc/<pid>/io". Sketch: "Updates every 2 seconds — CPU use is an estimate."

**7. Urgent windows are a red rectangle only.** `Bar/Bar.qml:233` encodes `is_urgent` solely as `Theme.danger` fill in the workspace map — no icon, shape, or text. Sketch: add a pulsing ring or "!" marker.

**8. Same concept, different delete glyphs inside Notes.** `Notes/NotesPanel.qml:95` uses `list-remove` for "delete the notebook and its notes" (the more destructive one), while `ControlCenter/SidebarNotes.qml:196` uses `edit-delete` for "Delete this note". Sketch: `edit-delete` + confirm for both.

**9. `edit-clear-all` means four different things.** `Files/FilesPanel.qml:376` "Tidy this folder" (non-destructive), `Terminal/TerminalAppWindow.qml:180,475` "Delete" (destructive), `ControlCenter/SidebarNotifications.qml:32` "Clear all", `Whiteboard/Whiteboard.qml:288` "Clear the page". Sketch: reserve `edit-clear-all` for bulk-delete only.

**10. Progressive-disclosure component exists but is barely used.** `Common/Advanced.qml:1-8` folds expert controls away, yet only `Settings/SettingsSound.qml:293` and `Settings/SettingsNetwork.qml:471` use it; `Settings/SettingsAppPermissions.qml` and `Settings/SettingsFirewall.qml` show everything at once. Sketch: wrap their env-var/bus-name/rule sections.

**11. Small treemap tiles are identified by color alone.** `DiskUsage/DiskUsagePanel.qml:153-156` gives each tile a unique hue; labels only render when `tile.width>46 && height>28` (`:167`). AT name exists (`:162`), but a colorblind sighted user sees unlabeled colored blocks. Sketch: hatch/pattern or always-on initials.

**12. Silent success on common actions.** `Mail/MailWindow.qml:281-302` (mark unread, star, archive) and `Feeds/FeedsWindow.qml:307` (mark unread) change state with no confirmation, while `PasswordGenerator/PasswordGeneratorPanel.qml:117` and `Authenticator/AuthenticatorWindow.qml:169` do show "Copied". Sketch: reuse #1's Toast for the silent ones.

**13. Unexplained abbreviation in a results view.** `Kundali/KundaliPanel.qml:140` appends bare `"(R)"` for retrograde planets, never expanded. Sketch: "retrograde (R)", or a legend.

**14. Dead-end playback error.** `MediaPlayer/MediaPlayerWindow.qml:246` "This file cannot be played" — no cause, no "open with…", no next step. Sketch: "Unsupported format — try another file or open with another app".

**15. Inconsistent expansion of "e.g." in labels.** `Settings/...` and `Terminal/...` mix `Tr.t("e.g., https://example.com")` with `Tr.t("for example")` (found across ~6 user strings). Sketch: standardize on "for example".

**16. Untranslated destructive user labels.** `Settings/SettingsUsers.qml:89` hardcodes `"Administrator" / "Standard"` and `Contacts/ContactsWindow.qml:190,214` hardcode `tip: "Remove"` — unlike the rest of those files. Sketch: wrap in `Tr.t()`.

**Skipped / not checked:** no runtime or visual verification (static read only); I did not re-audit contrast, focus, AT-SPI naming, or the eight already-logged tone items. Biggest risk: #1/#2 change shared components — verify no app relies on the current neutral styling of destructive icon buttons.

## VERBATIM: Test infrastructure & CI

# Thirteenth-pass audit — TEST INFRASTRUCTURE & CI coverage (static only)

Read `docs/GAPS.md`, `docs/GAPS-RESEARCH.md` (skipped logged items), then `tests/` (152 files), `dev/check.sh`, `dev/shell-test.sh`, all 78 `dev/shell-parts/*.sh`, `dev/session.sh`, `dev/Containerfile`, the 32 `dev/fake-*` tools, and workflows in `shani-builder`, `shani-pkgbuilds`, `shani-ci-commons`, `shani-testbed`.

## Counts (what's tested, how)

| Category | Count | Evidence |
|---|---|---|
| pytest files / test functions | 152 / 953 (`def test_`), 46 `@parametrize` | `tests/test_*.py` |
| — pure source-string assertions | ~88 (58%) | `test_gap_*.py`, `test_qml_patterns.py`, `test_wiring.py` |
| — bridge behavior (imports/calls bridge) | ~18 | `test_feeds_bridge.py`, `test_otp.py`, `test_mail_bridge.py` |
| — mixed (bridge + source read) | ~34 | `test_app_registry.py`, `test_cli_ipc.py` |
| — other | ~12 | `test_bridge_names.py`, `test_face.py` |
| Full-shell IPC integration | ~1067 `result … PASS/FAIL` sites; 17 SKIP | `shell-test.sh:13` + 78 shell-parts |
| Perf budgets | 7 (idle frames, RSS, open speed, files open/requests, leak, startup) | `shell-test.sh:127-180` |
| Visual/render | 49 captures; 261 surfaces documented | `dev/render.sh`, `docs/RENDER-COVERAGE.md:8` |
| A11y (AT-SPI) | ~20 surfaces, **conditionally skipped** | `shell-test.sh:196-221` |
| Tests with silent skip guards | 50/152 files | `skipif`/`importorskip` |

Fakes exist for every external dependency checked (podman, firewall-cmd, flatpak, gpg, nmcli, udevadm, gio, …); all 32 `dev/fake-*` are referenced — no clean-image fake gap found.

## Ranked gaps (value × ease)

1. **CI runs zero shell tests.** No `shani-shell/.github/workflows`; sibling workflows build/lint/package only — `shani-builder/.github/workflows/build.yml:15-22` (build+security), `shani-pkgbuilds/.github/workflows/lint.yml:20-37` (lint/package/security). Reusable `shani-ci-commons/.github/workflows/test.yml` never called for this repo. *Sketch: one workflow running `dev/check.sh unit` + `perf` with sibling checkouts.*
2. **Skips count as green.** 50 files skip on missing `node`/`gi`/ffmpeg/siblings; `dev/check.sh:128` greps only `passed`/`failed`. Hundreds of skips still print green. *Sketch: parse `N skipped`, fail above threshold.*
3. **Unit suite runs on the host, outside the test image.** `dev/check.sh:87` → `python3 -m pytest tests -q` (no `box()`); all deps are in `dev/Containerfile`. Host without node/gi → mass skips (gap 2). *Sketch: run `unit` inside `box()`.*
4. **Perf budgets excluded from default `all`.** `dev/check.sh:23,64` = `unit shell greeter setup polkit admin setup-polkit pam keyring`; the 7 budgets need separate `check.sh perf`. *Sketch: add `perf` to `all`/nightly.*
5. **A11y silently skips without `shani-testbed`.** `shell-test.sh:196,221`; mount conditional at `check.sh:39,68`. Static `tests/test_qml_a11y.py` (untracked) found ~84 unnamed IconButtons — the loudest signal is the one that skips. *Sketch: make `/testbed` mandatory for the a11y suite.*
6. **Real network dependency with SKIP fallback.** `shell-test.sh:1153` `curl https://api.open-meteo.com`; `:1158` prints SKIP. No fake (unlike `fake-osm.py`). *Sketch: `fake-open-meteo.py` on localhost.*
7. **One app has no test at all — Color Picker.** Excluded from generic `apps.sh` loop (state key `None`, `bin/shani:498`), explicitly skipped in `pad-reach.sh:33`; only mention is the skip-list. *Sketch: pointer-driven `ipc colorPicker` check.*
8. **Four apps have only "opens, no QML error" checks.** Password Generator (`apps.sh:140` only), Models, Studio, Screen Ruler (`render.sh:634` capture only) — no behavior test. *Sketch: one core-action assertion each.*
9. **Backup create/restore untested.** `dev/fake-backup.sh:12` implements `backup --json`, but only `shell-test.sh:2050-2062` (summary + `open home`) drives it; no snapshot taken/restored. *Sketch: one backup + restore assertion.*
10. **Permission boundaries untested under root.** `tests/test_copyjob.py:101` skips unreadable-file case ("running as root"); `apps.sh:210` checks read-only only via the probe's flag. *Sketch: run one suite unprivileged.*
11. **Sibling-repo skips; missing `/desk` unchecked.** `test_declared_deps.py:27-28`, `test_packaging.py:24`; `check.sh:38,89` mounts `$DESK` without `-d`, so a clean checkout mounts an empty dir and greeter/setup/pam get a missing KDL path. *Sketch: fail fast if siblings absent.*
12. **Timing-dominated shell suite.** `waitfor` 379× in `shell-test.sh`, 447× in parts, 325 `sleep`s; helpers `:49-60`, prior loaded-machine miss recorded at `:74`. *Sketch: central deadline helper + jitter-tolerant assertions.*
13. **Real D-Bus/process races in pytest.** `test_bt_agent.py:21,82`, `test_logind.py:26,120`, `test_mpris_player.py:43-78`, `test_obex_agent.py:21,88` — `importorskip("gi")`/`skip("no dbus-daemon")` with polling sleeps. *Sketch: shared private-bus fixture.*
14. **No positive controls for ~88 string checks.** Contrast `shani-builder/.github/workflows/build.yaml:76-90`, which plants a real leak line to prove its grep guard is live. *Sketch: planted-mutation assertion per critical string suite.*
15. **Render/visual checks never gate CI.** 49 captures guarded only by `test_cli_ipc_wiring.py`; excluded from `all` (gap 4).
16. **Fixed-duration media waits.** `tests/test_voice_recorder.py:63-74` (`sleep 1.2/1.0/0.3`), `shell-test.sh:1560-1562` assume wall-clock completion.

**Strengths worth noting:** Trash/destructive paths are unusually well covered (`files-ops.sh:50-60`, `files-nautilus.sh:19`, `apps.sh:261` firewall-never-permanent, editor save keeps perms/CRLF/symlink at `apps.sh:213-244`); every external tool has fakes; render coverage is source-derived and IPC-guarded.

Skipped: re-running anything live (static pass), plus the already-logged string-only, PKGBUILD-pin, QML-harness and dev-session-state items. Risk: the 88/18/34/12 split is a heuristic grep classification — spot-check before quoting it as exact.

---

# Twelfth pass — VERBATIM agent reports

## VERBATIM: Containers/virtualization depth

# Twelfth-pass gap research — Containers app & virtualization integration depth

**Scope:** static only. Read `shani/Modules/Containers/ContainersWindow.qml`, `bridge/containers.py`, `tests/test_containers.py`, `dev/shell-parts/containers.sh`, `dev/fake-podman.py`, `Ui.qml`, `shell.qml`, `ShellApps.js`, `bin/shani`, Cassini `tabs/containers.py` + `tabs/virtualization.py`, and `shani-docs` container/VM pages. No edits. Skipped prior-listed items (VMs Flatpak-only, Distrobox mentioned, Podman in Software).

**What exists:** one 389-line window with three tabs (Toolboxes / Containers / Images). Distrobox: create, enter, upgrade, export app, remove — all via `containers.py`. Podman: list, start/stop/restart/remove, logs, image-remove, prune. Everything runs rootless as the user. A thin state surface in `Ui.qml:74-80` drives a11y tests. Launcher id `dev.shani.Containers` (`bin/shani:542-543`, `ShellApps.js:34`). This is the first container audit; GAPS only mentions containers incidentally.

## Ranked gaps (value × ease)

1. **H×H — No custom image.** Four hardcoded chips only (`ContainersWindow.qml:24-29`); `box-create` takes `(name, image)` fixed to those (`181`, `bridge:145`). Add a validated image TextField (regex already at `bridge:35`).
2. **H×H — No name field.** `nextName()` auto-generates `ubuntu`, `ubuntu-2`… (`:109-113`). Add a text field checked with `NAME` (`bridge:34`).
3. **H×H — Podman containers have no shell entry.** `enter()` always runs `distrobox enter` (`:114-117`); only *toolboxes* open. For `!c.box`, run `xdg-terminal-exec podman exec -it NAME sh`.
4. **H×H — Export is one-way.** Only `box-export --app` (`:258-259`, `bridge:148-153`); no unexport, no list of already-exported apps, so re-export duplicates. Add `distrobox-export --app X --delete` + an "in menu" badge.
5. **H×H — No container creation at all for Podman.** Only management verbs (`:304-312`); docs promise `podman run -p/-v`, volumes and networks (`containers.md:37,71-99`). Add a "New container" form with image, ports, volume, network.
6. **M×H — No home/path choice.** `distrobox create` at `bridge:145` passes only `--yes --name --image`; home is always implicitly shared. Add `--home <path>` via `FolderPicker`.
7. **M×H — `--nvidia` / `--init` / `--ephemeral` / `--root` absent** (`bridge:145`) though GPU containers are a documented first-class feature (`containers.md:18`, `gpu-containers.md:146-177`). Four checkboxes appended to the create argv.
8. **M×H — No `--additional-flags`/`--mount`/`--env`.** `shlex` is imported (`bridge:27`) but unused for flags. One "advanced options" field; split with `shlex.split`.
9. **M×H — Logs are one-shot.** `logs --tail 300` returns a static string (`bridge:90-94`) rendered in a Flickable (`:314-335`). Add `logs -f` with `SplitParser` like `job`.
10. **M×H — App list misses user apps and locales.** `box_apps` scans only `/usr/share/applications/*.desktop` and reads plain `Name=` (`bridge:111-123`). Include `~/.local/share/applications` and prefer `Name[$LANG]`.
11. **M×M — No resource limits or stats.** `listing()` pulls state/ports/images only (`bridge:54-79`); no `podman stats`, no `--cpus`/`--memory`. Add a per-row CPU/RAM meter from `podman stats --no-stream --format json`.
12. **H×M — No "update all" or image-update signal.** Only per-box upgrade (`:227`, `bridge:154-155`); no bulk loop, no `podman pull`, no stale-image notification. Add one button looping `win.boxes` plus an image-age column.
13. **H×M — Toolboxes detected by Podman label only.** `box = labels.get("manager") == "distrobox"` (`bridge:65`); the shell never calls `distrobox list` (Cassini does, `tabs/containers.py:110`). A missing/renamed label silently downgrades a toolbox to an ordinary container (losing Open/Apps/Update). Union both sources.
14. **M×M — No snapshots.** No `commit`/restore verb anywhere in `bridge/main()` (`126-165`). Add `commit <name>` and a snapshot list with restore.
15. **M×H — No file-manager integration.** Home is shared but nothing opens it; no Files action in either delegate (`:206-265`, `:284-336`). Add "Open its home" → `xdg-open <path>`.
16. **M×M — No `.desktop` generation or icon-theme control** for ordinary Podman GUI apps; only Distrobox `--app` export exists. Generate `Exec=podman run --rm …` entries and pass `GTK_THEME`/`ICON_THEME` via gap 8.
17. **M×M — No compose support.** Docs teach `podman-compose up/down` (`containers.md:89-99`); the app never searches for `compose.y*ml`. Add a "Stacks" tab discovering `~/Developer/**/compose.y*ml` with up/down.
18. **M×H — No Settings defaults.** No container keys in `SettingsIndex.js`; distro choice is transient UI state (`:42`). Add default distro/image/flags keys and a Settings › Virtualization page.
19. **M×H — No handover between the two apps.** Header says "Cassini's Containers page stays the read-only inventory" (`:6`); Cassini enforces read-only by AST (`tabs/containers.py:7-12`). Neither links to the other. Add "Manage in Containers" / "View inventory" buttons.
20. **M×H — Tests are narrow and fake-only.** `test_containers.py:26-53` covers only list, stop, logs, create, apps, export, remove, prune; no test for restart, image-remove, box-upgrade, error branches, or tool-absent state. `dev/shell-parts/containers.sh:11-28` is gated on an a11y client. The `SHANI_PODMAN`/`SHANI_DISTROBOX` overrides (`bridge:32-33`) are never used by tests (they symlink into PATH, `test_containers.py:16-21`). Parametrize every verb and both missing-tool states.

**Comparison context:** GNOME Boxes/virt-manager remain deliberately out of scope (GAPS:1090; `virtualization.py:23-25` notes virt-manager is commented out of `shani-core` and gnome-boxes unpackaged). Docs overclaim here: "Pods pre-installed on every edition" (`containers.md:39`) and "BoxBuddy pre-installed on GNOME and KDE" (`distrobox.md:11`) describe external apps the shell only imitates; reconcile those claims with the built-in Containers window.

**Risk:** all verdicts are static; no Podman/Distrobox daemon, live export, polkit or GUI was available, so findings 3, 8 and 13 in particular need runtime confirmation before implementation.

Skipped: VM/Boxes/virt-manager feature parity, docs-only framing beyond the two stale claims above, and any edit — this pass was read-only.

## VERBATIM: Bluetooth/OBEX transfer depth

# Twelfth pass — Bluetooth/OBEX file-transfer depth

Static only. Prior passes covered pairing, codec, OBEX-agent bridge tests, Nearby/LocalSend and KDE Connect; those are skipped. Sources: `shani/Services/{BtAgent,BtSend,ObexReceive,Nearby}.qml`, `shani/Modules/ControlCenter/SidebarDetails.qml`, `bridge/{bt-agent,obex-agent,link}.py`, `bridge/shani_link/{obex_receive,bt_pair,bt_telephony,phone_bluez}.py`, `tests/*`, `dev/shell-test.sh`.

## Shell-fixable — ranked by value × ease

1. **Incoming push has no auto-accept for known/trusted devices.** Every push asks (obex-agent.py:99-109; shell-side only a `notify-send` with Accept/Decline at ObexReceive.qml:56-59). The agent already resolves the sender's BlueZ device on the system bus at :82-97 — reuse it to auto-accept when `Trusted` and a new setting allows. GNOME/KDE offer exactly this for trusted peers.
2. **No receive progress and no cancel.** obex-agent.py:111-128 subscribes to `PropertiesChanged` but reads only `Status` complete/error; `BytesTransferred` is ignored, and `Transfer1.Cancel` is never called. Sketch: emit `{"progress":…}` from the same signal and add a Cancel action that calls Transfer1.Cancel on the stored transfer path.
3. **An ignored push hangs forever.** obex-agent.py:107 keeps `pending[id]` until an answer; ObexReceive.qml:57 sets no `-t`, and `-A` implies `--wait` (verified via `notify-send --help`). The shani-link twin has `DECIDE_SECONDS = 60` (obex_receive.py:37,220) — port that: 60 s QML timer → `answer(id,false)`.
4. **No destination picker per file.** The target path is fixed at authorization time (obex-agent.py:104) from the global `obexDir`; the prompt shows only name and size (ObexReceive.qml:57-58). Sketch: add a FolderPicker to the push card and pass the chosen path in `answer()`.
5. **No Bluetooth transfer history.** `received` is a counter and `last` a single path (ObexReceive.qml:16-17); BtSend keeps nothing. Sketch: append `{device,file,size,when,dir,result}` to a persisted list shown in Settings > Network > Bluetooth — the shell's Nearby UI similarly keeps only the last three (GAPS-RESEARCH.md:455).
6. **Outgoing send has no progress, cancel, resume, or retry.** BtSend.qml:24-30 polls only the `Status` string every 0.5 s for a hard 600 iterations (5 min), no `BytesTransferred`, no `Transfer1.Cancel`, no error detail; :38-43 reports only success/failure via `notify-send`. Sketch: emit progress/cancel lines from the same loop and expose a transfer card in `SidebarDetails.qml:282-299`.
7. **One file per send.** `BtSend.qml:12` is a single `file` string, :23 one `SendFile`; Share.qml:22 builds one target per device. Sketch: make `pending` an array and loop CreateSession→SendFile sequentially.
8. **Send does not connect a paired-but-disconnected device.** BtSend.qml:14 filters on `paired` only; :41 gives the vague "is it paired, on and accepting files?" hint. Sketch: call `device.connect()` before `sendTo`, then surface the gdbus error string.
9. **HFP call-audio routing exists in the bridge but no shell UI.** bt_telephony.py:224-249 already implements `audio_route()`/`set_audio_route()` ("pc"/"phone" via `RejectSCO`), yet bridge/link.py exposes only dial/answer/hangup (:251-304) and the call card has no routing toggle. Sketch: add `link.py audio-route` and a button; this is the direct fix for "ring in silence" cases, distinct from the WirePlumber A2DP↔HFP auto-switch gap in GAPS-RESEARCH.md:855.
10. **PBAP call history is implemented in shani-link but not reachable from the shell.** phone_bluez.py:478-494 pulls `int/cch` vCards; bridge/link.py:121-128 `cmd_calls()` reads only cached `calls_log` rows. Sketch: add `link.py phone-calls <device>` and a "Phone's recent calls" row in the Phone panel.
11. **No FTP/browser of phone files anywhere.** `phone_bluez.py` implements MAP/PBAP/OPP only (:47-52); "ftp" appears only as NFC URI constants (shani-link/nfc.py:67-71). Sketch: obexd `Client1.CreateSession(ftp)` + `Filesystem1.ListFolder/GetFile`, surfaced as a paired-phone node in Files. Needs a phone that offers FTP and obexd FTP support — high value, highest effort here.
12. **Per-device auto-connect is absent.** One global switch (SettingsNetwork.qml:443-450) drives BtAgent.qml:52-66, whose regex `/^(audio|input)/` excludes phones, watches and everything else. Sketch: a per-address `autoConnect` set in Settings and use it in `reconnect()` instead of the icon regex.
13. **Connection profiles are not exposed.** SidebarDetails.qml:141-168 shows a single Connected/Paired state; bt_pair.py:312 already reads `Device1.UUIDs`. Sketch: show A2DP/HFP/PBAP/MAP profile chips from `UUIDs` and call `ConnectProfile`/`DisconnectProfile` — this also tells the user why MAP/PBAP failed (phone_bluez.py:26-28 requires per-device consent on Android).
14. **Trust is set before pairing succeeds.** SidebarDetails.qml:157 sets `modelData.trusted = true` then calls `pair()`; bt_pair.py:347-355 sets Trusted only after a successful Pair. Sketch: move the trust assignment into the success callback.
15. **No device rename/alias.** SidebarDetails.qml:146-149 renders `modelData.name` read-only; bt_pair.py's `Device` has no alias setter. Sketch: a rename row calling `bluetoothctl alias <addr> <name>` via `Process`.
16. **Pairing prompts have no timeout; displayed passkeys do.** BtAgent.qml:47 times out only `show`; `ask` (:15) and bridge/bt-agent.py:71-75 wait indefinitely. Sketch: the same 60 s timer calling `answer(false)`.
17. **The default agent answers pairings it did not start.** bt-agent.py:137-138 requests the global default with KeyboardDisplay, while shani-link's pairing flow deliberately uses a private connection with its own agent (bt_pair.py:9-15). Sketch: ignore `AuthorizeService`/confirm for addresses outside an active shell pairing session.
18. **Single OBEX agent slot with no handoff.** obex-agent.py:151-158 exits when another agent holds obexd (tested: test_obex_agent.py:154-158); shani-link's receiver backs off inside niri (obex_receive.py:84-92,168-173). Sketch: one shared agent (or a handoff switch) so a Chronoa-driven session does not silence the shell receiver.

## Needs BlueZ / hardware / other stack

- **No NAP server / no obexctl, sdptool, pand, rfcomm** in the image (FINDINGS.md:775); FTP profile support must be verified on the paired phone before gap 11 is worth building.
- **Android PBAP/MAP consent is per-device and external** (phone_bluez.py:26-28): 0x46 from PBAP and silence from MAP are phone-side settings, not shell bugs.
- **A2DP↔HFP automatic switching** needs a WirePlumber Lua policy (GAPS-RESEARCH.md:855), not a QML change.
- **Codec choice and HFP hardware audio silence** are already listed and skipped.

## Comparison

GNOME Bluetooth provides per-device Files transfer with a progress dialog, a Trust toggle, rename, and profile switches; KDE Connect adds file-manager context actions and a transfer list; Android Quick Share adds fast discovery, multi-file/recipient sends, known-device auto-accept and resumable history. The shell has OPP send/receive but none of the transfer-management layer: no progress, cancel, history, per-file destination, or trust rules.

**Skipped / not checked:** no live BlueZ, obexd or phone — everything above is static, including the `-A` semantics which I verified from `notify-send --help` rather than a real notification daemon. **Risk:** the shell's outgoing OBEX send path has no test at all (GAPS.md:232-233); a send-command failure could hide additional D-Bus issues beyond gaps 6-8.

## VERBATIM: WebApps/PWA depth

## Scope read
Read `GAPS.md`, `GAPS-RESEARCH.md`, `Services/WebApps.qml`, `SettingsWebApps.qml`, `bridge/portal.py`, `Common/Settings.qml`, `shell.qml` IPC, `Launcher.qml`, `Dock.qml`, both portal configs, and the `shani-docs` software tree. Skipped as instructed: broken app-mode, no icon fetch, no manifest/share target, no isolated profile, no import/export, browser-integration defaults. All verdicts static.

## Ranked gaps (value × ease) — `[S]` shell-fixable, `[B]` browser/Flatpak-level

1. **[S] Tapping a web-app row deletes it; there is no open or edit.** `SettingsWebApps.qml:16-27` — whole-row `onClicked` splices the entry out; the `✕` at `:21` is just decoration, and the only other action is Add (`:30-35`). Sketch: make row click `gio launch` the generated `.desktop`, add an explicit × remove button and an Edit action reusing the add dialog.
2. **[S] No URL validation, secure-context check, or untrusted-site warning.** `SettingsWebApps.qml:97` checks only `urlInput.text === ""`; `WebApps.qml:61-63` merely percent-escapes shell characters. `http://`, `file://`, `javascript:`, `data:` are accepted silently, and the preset list (`:51-63`) is all HTTPS so there is no precedent for free-form safety. Sketch: require `https://` (allow `http://localhost`), reject non-web schemes, show a one-line "this site can store data / send notifications" consent.
3. **[S] No per-app refresh, cache clear, or site-data clear.** `WebApps.qml:24-39` exposes only add/remove; `:89-101` writes a static Exec with no Actions. "Update" means re-opening the same URL and trusting the browser cache. Sketch: add per-app "Reload / Forget site data" actions (browser CDP/JS hook or, with an isolated profile, delete its dir).
4. **[S] No launch-by-name IPC — the promised "reveal" hook does not exist.** `WebApps.qml:107` comments `ipc call vgs.webapps invoke open <name>`, but `shell.qml:1218-1219` exposes only `webappAdd` / `webappRemove`. Sketch: add `webappOpen(name)` that `gio launch`es `prefix + safeName + ".desktop"`; wire Chronoa/launcher/share to it.
5. **[S] Web apps never appear under the launcher's "Internet" chip.** Generated entry uses `Categories=Network;WebBrowser;` (`WebApps.qml:95`), but the launcher chips are `"Internet"` and match `a.categories` directly (`Launcher.qml:264,287,747-753`); the only alias is `AudioVideo→Media` (`:265`), even though `SoftwareWindow.qml:44` already maps `Network→Internet`. Sketch: add `Network: "Internet"` to `categoryNames` (and match aliases), or emit `Categories=Internet;`.
6. **[S] No edit/rename, reorder, or schema/dedupe.** Only add/remove exist (`SettingsWebApps.qml:14-35`); data is an untyped `property var webApps: []` (`Common/Settings.qml:603-605`); `removeApp` filters by name so duplicate names all vanish together (`WebApps.qml:37`). Sketch: store a stable `id`, validate/dedupe on write, add inline edit + up/down.
7. **[S] Sanitized-name collisions silently overwrite.** `safeName = name.replace(/[^a-zA-Z0-9_-]/g,'_')` (`WebApps.qml:86`) is the filename (`:99`) and identity, so "My App" and "My_App" produce one `.desktop`. Sketch: key by generated id/UUID; detect collisions at add time.
8. **[S] No "open at startup" for a web app.** Desktop entry (`WebApps.qml:89-101`) has no autostart file or `X-GNOME-Autostart`; no setting exists. Sketch: write the same entry into `~/.config/autostart/` behind a per-app flag.
9. **[S] No dock-pin / workspace-assign action from the web-app row.** Generic pinning exists (`Dock.qml:188,571`) and `StartupWMClass=shani-webapp-…` is emitted (`WebApps.qml:98`), but nothing connects a web app to either; no window rule targets that class. Sketch: context menu "Pin to dock" → `Dock.pinApp(id)`, "Assign workspace…" → niri window rule on the class.
10. **[S] No per-app keyboard shortcut.** No keybinding is generated and the shortcut settings have no hook for web-app ids. Sketch: optional `shortcut` field → a shani niri keybind include file.
11. **[S] Feature is undocumented.** No page in `shani-docs/docs/software/`; the only PWA mention is `troubleshooting.md:600` as a Waydroid fallback. Sketch: `docs/software/web-apps.md` + manifest/nav entry covering add, limits, and data location.
12. **[B] No PWA install pipeline at all.** Manual free-text URL only (`SettingsWebApps.qml:72-86`); no beforeinstallprompt capture, no manifest parse, so display mode (`standalone`/`minimal-ui`/`fullscreen`), theme colour, splash/icon and offline scope are never set. (The missing manifest/share target itself is already filed; this is the rest of the flow.) Sketch: needs a shell-hosted web view plus manifest parser — not achievable via the current `sh -c` launcher.
13. **[B] No service worker / offline start.** Entries open a URL in a browser, so offline availability is entirely the remote site's; the shell has no offline state, no "available offline" flag, no retry. Sketch: browser-level; shell could at most surface an offline badge via Network state.
14. **[B] Push notifications bypass the shell entirely.** `niri-portals.conf:8` delegates `Notification=gtk`; `data/portal/shani.portal:3` and `bridge/portal.py:34-43` implement only `FileChooser`. PWA push never reaches `Notifs.qml` or the rules engine, so no per-app notification toggle or rule can act on it. Sketch: implement `org.freedesktop.impl.portal.Notification` in `portal.py` and register it in `shani.portal`.
15. **[B] Per-app permissions and storage quota are not expressible.** No origin-level permission or quota field in the data model (`Common/Settings.qml:603-605`); with no isolated profile these inherit one browser origin's site settings and shared storage. Sketch: browser site-settings scope; shell can only link out, not enforce.
16. **[B] All web-app UX actions are browser-side and currently unreachable.** Back/forward, reload, "open in browser", copy URL and share would be browser UI or a shell menu over the window; the generated Exec never reaches the browser with `--app` (the already-filed Flatpak/app-mode bug), and no shell context menu exists for generated `.desktop` apps. Sketch: fix app-mode first, then add a window/context menu.
17. **[B] Icons dir is allocated but unused, so uninstall cannot be clean.** `WebApps.qml:42` creates `iconsDir`; the scraping code is comments only (`:106-109`), and `removeApp` (`:35-39`) touches only the settings array. Once icons/profiles do exist, removal will leave them orphaned. Sketch: make `removeApp` delete icon + profile + autostart files in the same sync script.

## Ponytail note
Skipped runtime/browser verification (no QML runtime, Flatpak Vivaldi, or live portal bus) and the already-listed items above; everything is static. Main risk: item 5 depends on Quickshell not normalising `Network→Internet` internally, and item 14 assumes PWA push goes through the portal (Chromium may use its own notification path) — both need a real session to confirm.

## VERBATIM: Keyboard shortcut conflicts/discoverability

# Twelfth-pass: keyboard shortcut conflicts & discoverability (static only)

Skip list honored. **Negative result first:** no direct niri-vs-app same-combo collision exists in the shipped config — every global bind uses `Mod` (`session.kdl:147-300`) and every app bind uses `Ctrl` or a bare key. Conflicts are instead *created by customization*, *within the app layer*, or *by unteachability*.

### High value × easy

1. **On-screen keyboard cannot send Super/Meta — all global shortcuts are touch-only unreachable.** `Services/Osk.qml:29-33` (`ctrl`/`alt` only), `Modules/Osk/Keyboard.qml:322-323` (only Ctrl/Alt keys), while `session.kdl:150-290` binds almost everything to `Mod`. Sketch: add `Osk.meta` + a Super key + `wtype -M super` in `modArgs()`.
2. **Custom binds can silently break Ctrl+C/V/Z/S in every app.** `SettingsShortcuts.qml:28-34` `takenBy()` checks only niri binds + other custom binds; `:108-112` captures Ctrl combos; `InputConfig.qml:146` writes any `/^[A-Za-z0-9+_]+$/` combo as a *global* grab. Sketch: reject Ctrl/Alt-only combos in `takenBy()` using the existing conflict banner.
3. **Annotate's bare `E` clear is unrecoverable.** `Annotate.qml:44` `clear()` sets `strokes=[]`; `undo()` at `:43` only pops one stroke, so `Z` after `E` restores nothing. Sketch: make clear one undoable snapshot and two-tap confirm.
4. **No surface lists app-internal shortcuts.** `SettingsShortcuts.qml:39-49` shows niri binds only; `Tour.qml:31-35` and `LauncherActions.qml:69` show ~8 global keys. Viewer's ~20 bare keys (`Viewer.qml:33-51`) and Files' ~30 (`FilesPanel.qml:67-185`) are nowhere. Sketch: declarative `shortcutHint` per app, aggregated into a filterable sheet.
5. **Calculator's window-level Return/Enter Shortcut overrides focused TextFields.** `Calculator.qml:575-578` uses QML `Shortcut` (default `Qt.WindowShortcut`, per Qt 6 docs), competing with `onAccepted` on `:344-347`, `:477`, `:479`. Sketch: scope to the calculator display or move to `Keys.onReturnPressed` there.

### Medium value × easy

6. **Escape is a no-op in TextEditor with >1 tab.** `TextEditorPanel.qml:451-458` `leave()` handles finding and single-doc only. Sketch: Escape closes the active tab (one level back) first.
7. **Mutation modifier is inconsistent across drawing/viewer apps.** Annotate uses bare `Z/E/S/1-5` (`Annotate.qml:90-94`), Whiteboard uses `Ctrl+Z/Ctrl+S` (`Whiteboard.qml:119-121`), Video Trimmer bare `I/O/S` (`VideoTrimmerPanel.qml:30-32`), PdfReader bare `R/F/W/P` (`PdfReader.qml:232-239`). Sketch: require Ctrl for all state-changing keys, or show an in-app key legend.
8. **Shared `KeyFocus` has no Home/End/PageUp/PageDown.** `Common/KeyFocus.qml:105-121` handles only Enter/Space/Menu/F10/arrows/Tab. Sketch: map Home/End to first/last in region, PgUp/PgDn to `move(±rows)`.
9. **Launcher's Ctrl+Y Quick Look is undocumented in the UI.** Implemented at `Launcher.qml:652-659`; result subtitles at `:316-340` list only Enter/Shift+Enter/Ctrl+P/Shift+Delete. Sketch: append "Ctrl+Y Quick Look" to file-result subtitles.
10. **"Change keyboard shortcuts" lands far from the editor.** `LauncherActions.qml:70` → `openSettings("input")`; `SettingsShortcuts` sits at `SettingsPage.qml:1440`, after ~40 input controls. Sketch: add a `shortcuts` sub-category that opens scrolled to that section.

### Medium value / more work

11. **Escape means four different things across surfaces.** Layered unwind (`PdfReader.qml:226`, `Viewer.qml:31`), close-everything (`QuickPanel.qml:98`, `Whiteboard.qml:117`, `Magnifier.qml:66`, `Ring.qml:148`), no-op (#6), refocus (`LockScreen.qml:191`, good). Sketch: one `goBack()` contract: popup → edit mode → surface.
12. **Three-key a11y combos have no one-handed path.** `session.kdl:157-159,163` (read aloud, magnifier, annotate, captions) need Mod+Alt+letter; OSK has sticky Ctrl/Alt but not Meta (#1). Launcher actions exist for some (`LauncherActions.qml:87-89`), not annotate. Sketch: sticky Meta + launcher entry for annotate.
13. **Redo combos and coverage diverge.** Files supports both `Ctrl+Shift+Z` and `Ctrl+Y` (`FilesPanel.qml:142-148`), TextEditor the same (`TextEditorPanel.qml:435-436`), WindowLayouts has undo only (`WindowLayouts.qml:35`). Sketch: standardize on Ctrl+Y and add redo to WindowLayouts.
14. **Shortcut-search skips custom binds.** `SettingsShortcuts.qml:38-40` filters only `page.binds`; custom binds at `:53` are never filtered. Sketch: apply the same query to the custom-bind model.
15. **`Mod+Escape` shortcuts-inhibit has no discoverability.** `session.kdl:296` has no `hotkey-overlay-title` and no Settings toggle; an inadvertent press disables all global binds until the same combo is found again. Sketch: title it and surface an OSD/Settings status.

Skipped: the listed shortcut items, Super+Alt+S, and bare-Q/bare-W/zoom-modifier findings. Risk: Qt `Shortcut` priority (#5) is inferred from documented default context, not runtime-verified; all findings are static.

## VERBATIM: niri integration and extensions

## Scope

Read GAPS.md and GAPS-RESEARCH.md (all 11 passes) plus `Niri.qml`, `NiriConfig.qml`, `WindowRules.qml`, both `WindowLayouts.qml`, `InputConfig.qml`, `Screenshots.qml`, `Ring.qml`, `LauncherActions.qml`, `OverviewSearch.qml`, `Scratchpads.qml`, `shell.qml` IPC, `NiriBinds.js`, `dev/niri/*.kdl`, `dev/session.sh`, and the 142-action niri 26.04 action list from `shani-pkgbuilds/cache/pacman_cache/niri-26.04-1-x86_64.pkg.tar.zst` (bash completion). Skipped every listed item (window-rule properties, gestures, named workspaces, monitor swap, workspace drag, always-on-top, thumbnails, Activities, session restore, crash recovery).

**Already exposed — do not re-file:** `screenshot-window` (Ring.qml:61), `focus-window-or-workspace-*` (OverviewSearch.qml:78), dynamic cast (LauncherActions.qml:63-65), `unset-workspace-name` (Niri.qml:229,282), `close-window` + force-close (Niri.qml:300,458), global focus-follows-mouse (InputConfig.qml:94). These are KDL-bind-only or hardwired to one surface, not generally addressable.

## Shell-exposable gaps, ranked (value × ease)

| # | Gap + evidence | One-line sketch |
|---|---|---|
| 1 | **No third-party extension surface at all.** No manifest dir, no plugin loader: every bar widget, dock tile, launcher action and settings page is a literal `LazyLoader { source: "Modules/…" }` (shell.qml:114-155) or a hardcoded IpcHandler (shell.qml:258+). No `manifest` string exists in any QML/JS. | Scan `~/.local/share/shani/extensions/*/manifest.json` (slot, qml, ipc) → Loader per bar/dock/launcher/settings slot + dynamic IPC dispatch; this is the Waybar-module / Plasma-plasmoid / GNOME-extension equivalent. |
| 2 | **Hand edits to shell-owned includes are destroyed.** `WindowRules.qml:63-67` regenerates the whole `shani-windows.kdl` file; line 64 says so. `NiriConfig.qml` validates syntax but never preserves unknown blocks. | Emit only marker-delimited blocks and merge, or parse+retain unrecognised `window-rule {}` blocks before writing. |
| 3 | **No diff / history / manual restore for config changes.** One `.prev` copy, deleted on success (NiriConfig.qml:40-43,77); automatic undo only on `ConfigLoaded.failed` (80-85); `rejected` counter is not surfaced (21-23). | Keep timestamped backups under `~/.local/share/shani/niri-config/`, show `diff -u` in Settings, add `configRestore(idx)` IPC. |
| 4 | **Preset width/height actions never exposed.** `switch-preset-column-width` and `switch-preset-window-height` are KDL binds only (dev/niri/session.kdl:279,286); niri 26.04 also has `*-back` and `switch-preset-window-width`. WindowLayouts uses only `set-column-width` percentages (Services/WindowLayouts.qml:106-141). | Add `widthPreset(next)` / `heightPreset()` IpcHandler functions + Ring/Quick Settings tiles. |
| 5 | **`toggle-keyboard-shortcuts-inhibit` unreachable outside the KDL bind** (session.kdl:296). Matters for screen sharing, remote control and dictation. | IPC `shortcutsInhibit()` plus a Quick Settings toggle (no state query exists — track locally). |
| 6 | **`screenshot-window` fires blind at the focused window** (Ring.qml:61); Screenshots.qml:112 only does screen. No capture in the window menu (GAPS-RESEARCH:894). | `windowScreenshot(match)` → focus `Niri.findWindows(match)[0]` then `Niri.action("screenshot-window")`. |
| 7 | **Column-level moves/swap absent from the shell.** `move-column-to-workspace{,-down,-up}`, `move-column-to-index`, `move-column-to-monitor-*` are KDL-only or unused; `Niri.moveWindowTo` uses `move-window-to-workspace` (Niri.qml:193-201), splitting the column. Column swap never called (GAPS-RESEARCH:258). | WindowMenu "Move whole column to…" → `move-column-to-workspace`; add `swap-column-left/right` IPC. |
| 8 | **No apply-config-without-restart path.** niri 26.04 has `niri msg action load-config-file`; the shell only writes includes and waits for niri's auto-reload (NiriConfig.qml:68-86). | Settings > Developer "Apply config file…" → `niri validate -c` then `load-config-file` (reuses existing preflight). |
| 9 | **Urgency is display-only.** `is_urgent` tracked (Niri.qml:404-411); niri actions `set-window-urgent`/`unset-window-urgent`/`toggle-window-urgent` unused. | "Ping this window" in dock/window menu; `windowUrgent(match,on)` IPC. |
| 10 | **Interactive `niri msg pick-window` unused.** Shell overlays cannot click underlying windows, so a "choose a window" flow has no cheap implementation today. | IPC `pickWindow()` parses the picker's id → feed `Niri.findWindows`/`focusWin`. |
| 11 | **Single-socket assumption breaks nested/second sessions.** `Niri.qml:23,431-434` binds one `NIRI_SOCKET`; dev/session.sh:202 picks `ls … | head -1`; every action shells out to bare `niri msg` (Niri.qml:237). A nested test compositor is invisible and actions can hit the wrong one. | Parameterise the service by socket path, export it to child processes, add a Dev selector. |
| 12 | **Focus-navigation actions unused.** `focus-workspace-previous`, `focus-window-previous`, `focus-window-top/bottom`, `center-visible-columns` exist in niri 26.04 but have no IPC/palette (GAPS-RESEARCH:272). | Add to the `window*` IPC family and the Ring/overview action set. |
| 13 | **Workspace rename is monitor-warping and index-only.** `renameWorkspace` forces `focus-monitor` (Niri.qml:279-284); IPC exposes only `renameWorkspaceAt(idx,…)` (shell.qml:906), so a workspace on another monitor can't be renamed/unset by id. | `workspaceRename(id, name)` using `set-workspace-name --workspace <id>` (empty name → unset). |
| 14 | **`toggle-window-rule-opacity` action unused**, so the window-rule opacity property that niri 26.04 supports has no runtime toggle (cf. GAPS-RESEARCH:893). | IPC `ruleOpacity()` + WindowMenu row. |
| 15 | **`niri msg layers` / `pick-color` split.** `pick-color` is in shell.qml:481; `layers` is unused — no in-shell layer-surface inspector for the shell's own panels. | Dev IPC `layers()` rendering the JSON in LogsPanel. |
| 16 | **IPC discoverability for extensions.** ~519 functions, no `listIpc`/`describe`/tracer (GAPS-RESEARCH:861-862); a plugin registry (gap 1) cannot advertise or be debugged without it. | Reflect `IpcHandler` names + signatures into `state()` and log invocations. |

## Compositor-level — out of scope (confirmed, not new)

Focus-follows-mouse **per workspace** (niri 26.04 only has the global `input.focus-follows-mouse` the shell writes at InputConfig.qml:94); drag-to-edge event, gestures, always-on-top, window thumbnails, Activities, colour management, per-output VRR/refresh (GAPS-RESEARCH:816), compositor session manager, XWayland scaling. All already listed; this pass adds no new ones.

## Ecosystem comparison

Waybar/Polybar expose module lists in config, eww a widget DSL, Plasma KPackage plasmoids, GNOME extensions a loader API. Shani has only Hooks (event scripts) and matugen templates — good for *behaviour*, not for *surfaces*. Gap 1 is the single structural difference; gaps 2-3 are the config-safety price of owning the include files.

Skipped: runtime verification (static only), and I did not re-check the already-listed niri items. Risk: action names verified against the 26.04 package, but `pick-window`/`load-config-file` argument shapes were not executed; gap 5 has no queryable state, so the toggle may desync if the KDL bind is used.

## VERBATIM: Context menus depth

# Context menus — 12th-pass deep gap audit (static, read-only)

**Scope/method:** all app panels in `shani/Modules/` plus shell surfaces; grep for `RightButton`, `onPressAndHold`, `Hold.*`, `menuable`, `Accessible.MenuItem`, `Menu{}`/`Popup{}`, then targeted reads. Skip list honoured (Files *action set*, desktop right-click, launcher→dock pin, notification long-press, Open With, bar app menu).

**Structural finding:** there is **no shared context-menu component and no `Menu{}`/`Popup{}` anywhere** in ~93 modules. Every menu is hand-rolled `Glass`+`Repeater`+`Rectangle`+`KeyFocus` (Dock.qml:542-613, FilesPanel.qml:1347-1403, DesktopIcons.qml:297). Only Files, Dock, desktop icons and the bar app menu have a real menu; every other app row/field/image/tab has none. `KeyFocus.qml:114` does wire Menu/Shift+F10 to `menu()`, but only 8 call sites set `menuable: true`.

Ranked by (value × ease). Sketches are one-liners.

## Ranked gaps

1. **Files menu never takes keyboard focus on open.** `FilesPanel.qml:3005-3011` sets `menuEntry/menuX/menuY` but omits `Ui.focusFirst(menuBox)`; Dock does it at `Dock.qml:539`. Menu-key users land on the file, not the menu. *Sketch: add `Ui.focusFirst(menuBox)` to `openMenu()`.*

2. **Escape doesn't dismiss the Files menu.** Escape handler at `FilesPanel.qml:38-65` checks ~14 overlays but not `menuEntry`; it navigates up a folder or hides Files. *Sketch: add `win.menuEntry` to the first `if` and clear it.*

3. **Files menu items are invisible to screen readers.** Delegate at `FilesPanel.qml:1364-1401` has no `Accessible.role/name/onPressAction`; its only label lives in `KeyFocus`, which is `Accessible.ignored: true` (`KeyFocus.qml:38`). Dock gets this right (`Dock.qml:588-590`). *Sketch: copy Dock's three Accessible lines into the Files delegate.*

4. **Files file menu is mouse-only — no long-press.** `FilesPanel.qml:884-912` and `1006-1031` accept `RightButton` and use `Hold` nowhere; touch cannot open a file menu (and `drag.target` competes with a hold). *Sketch: add `Hold.state/press/hold` + `onPressAndHold: openMenu(...)`.*

5. **No text-editing context menu anywhere.** `Common/TextField.qml:31` (raw `TextInput`), `TextEditorPanel.qml:716-738`, `NotesPanel.qml:337-345`, `PdfReader.qml:499-513`. Right-click yields nothing: no Copy/Cut/Paste/Select All/Undo/Redo. GTK4, KDE and macOS all provide this on every `GtkEntry`/`QLineEdit`/`NSTextField` by default. *Sketch: one `TextContextMenu.qml` attached to the shared field + the three `TextEdit`s.*

6. **No shared context-menu primitive** (root cause of 1-3, 18). Three bespoke copies diverge. *Sketch: extract a `MenuSurface.qml` with model `{label,icon,sep,danger,run}`, focus-first, Escape, and Accessible.MenuItem built in.*

7. **TextEditor tabs have no context menu.** `TextEditorPanel.qml:506-515` accepts only `LeftButton|MiddleButton`; no Close Others/Close All/Close to Right/Save/Copy Path. *Sketch: accept RightButton → tab menu, reuse `closeTab(i)`.*

8. **Photos photo tiles have no menu.** `PhotosWindow.qml:390-426`: left-click only; Slideshow/Trash/Adjust are 22 px hover buttons (`414-428`) with opacity tied to `containsMouse`, so no right-click/long-press and no Copy/Share/Properties/Set-as-wallpaper. *Sketch: `onPressAndHold`/right-click → `FileActions.offer([path])`.*

9. **Mail message rows have no menu.** `MailWindow.qml:135-142` uses `ListRow { onClicked: Mail.read(...) }`; Mark read/unread, Flag, Archive, Delete, Reply/Forward exist only in the detail toolbar (`274-307`). Geary/Gmail expose these per-row. *Sketch: right-click row → menu calling `Mail.flag/archive/markUnread/remove`.*

10. **Viewer image right-click and long-press only rotate.** `Viewer.qml:352-377` — both gestures map to `Viewer.rotate()`; no image menu (Copy, Save As, Set as wallpaper, Properties, Share, Print). Touch parity is good, action coverage is not. *Sketch: hold/right-click → `FileActions.offer([Viewer.file])`, keep rotate on double-tap.*

11. **Music library album/song rows have no menu.** `MusicLibraryView.qml:100,190`: `onClicked` only; no Play next, Add to queue, Add to playlist, Delete, Show in folder. *Sketch: right-click song → queue/playlist menu.*

12. **Calendar events have no menu.** `CalendarPanel.qml:725,804`: `MouseArea { onClicked: win.viewEvent(modelData) }`; no Edit/Delete/Duplicate or right-click quick-create on empty day cells. *Sketch: right-click event → Edit/Delete; right-click day → New event.*

13. **Contacts rows have no menu.** `ContactsWindow.qml:457-465`: `rowArea` is `acceptedButtons: Qt.NoButton`, second MouseArea left-click only. Call/Message/Email/Share vCard/Edit/Delete are scattered toolbar buttons. *Sketch: right-click row → grouped action menu.*

14. **Feeds feed and article rows have no menu.** `FeedsWindow.qml:78-86,217-225`: `ListRow { onClicked }` only; no Mark read, Save, Open link, Copy link, Unsubscribe. *Sketch: right-click row → `Feeds.markUnread/toggleSave/open`.*

15. **Tasks rows have no menu.** `TasksWindow.qml:164-172`: `rowArea` NoButton + check MouseArea; Edit/Delete/Set due/Repeat only via hover icons (`221-229`). *Sketch: right-click row → Edit/Delete/Repeat/Due.*

16. **Terminal host rows have no menu.** `TerminalAppWindow.qml:112-133,159-182`: `rowArea` NoButton; Connect/Test/Browse/Edit/Delete are always-visible toolbar icons. *Sketch: right-click host → same actions as a compact menu.*

17. **PdfReader has no page/selection menu.** `PdfReader.qml:499-513` text mode is a read-only `TextEdit` (selectable, no menu — `Copy` only exists as toolbar icon `276`); thumbnails/annotations likewise. *Sketch: right-click page text → Copy/Select All; right-click page → Bookmark/Mark up/Print.*

18. **Menu presentation is inconsistent (icons, separators, submenus).** Files menu has icons (`FilesPanel.qml:1376`) but no separators; Dock has `sep` flags (`Dock.qml:562-567`) but no icons (`587-601`); no submenu support anywhere (e.g. TextEditor colours, Media playback speed remain flat toolbars), despite `Accessible.ButtonMenu` existing in `WindowMenu.qml:175`. *Sketch: shared model with `icon`/`sep`/`children`, one renderer.*

19. **Bar right-click actions are mouse-only.** `Bar.qml:181-184,618-621,824-827` set `hasMenu: true` so Menu-key works via `Chip.qml:69`, but chips have no `Hold` (unlike Dock `499`, Island `309`, Tile `110`); launch-mode/player-next/DND toggles are unreachable by touch. *Sketch: add `Hold` to `Chip.qml` and route `swallowed || RightButton` to `rightClicked()`.*

## Comparison
GNOME/GTK4 gives every entry and view a `GtkPopoverMenu` (standard Undo/Cut/Copy/Paste/Select All), per-file menus in Nautilus, and event/message row menus; KDE QML uses `Menu`/`MenuItem` with standard roles; macOS `NSMenu` adds accessibility actions and standard Edit selectors, iOS supplies long-press context menus. Shani has the keyboard/scroll-reader scaffolding (`KeyFocus`) but almost no menus to attach it to — items 1-4 are the cheapest quality win, item 5 the highest-value one.

**Skipped/not checked:** actual runtime rendering and AT-SPI output (static only); the six listed prior-pass items; non-listed utility apps (Settings, Launcher, etc.) beyond the named set. **Risk:** adding long-press to Files tiles (`4`) must not fight `drag.target`, and a shared menu component (`6`) would touch Dock/desktop menus that prior passes already verified.

## VERBATIM: Authenticator, Password Generator, Kundali depth

# Twelfth-pass gap research — Authenticator, Password Generator, Kundali / Panchang

All static. Skips honored (digits/period/algorithm UI, export/backup, clipboard clear, refresh tick; look-alikes/length/word-count/entropy/keyring/GPG; Kundali timezone, nine unwired bridge commands, visual chart, city search, export, ayanamsa). Ranked by value × ease.

| # | Gap | V/E | Evidence | Sketch |
|---|-----|-----|----------|--------|
| 1 | **Panchang computes 15 fields, UI shows 5** — `masa`, `paksha`, `ritu`, `ayana`, `kali/shaka/vikram_year`, sun/moon longitude, ayanamsa are silently dropped. | H/H | `KundaliPanel.qml:131-136` vs `shani-chronoa/astronomy.py:248-315` | Render the remaining 10 in the result block. |
| 2 | **No HOTP** — counter-based `otpauth://hotp/` is explicitly rejected; `tests/test_otp.py:59` pins that rejection as intended. | H/H | `bridge/otp.py:75-76` | Parse `hotp`, store `counter`, add `hotp()` (RFC 4226) and a "next code" button. |
| 3 | **No strength estimate** — only length is offered; a weak 20-char pattern looks identical to a strong one. | H/M | `PasswordGeneratorPanel.qml:132-145` | Score each candidate with zxcvbn locally; show label + bar, regenerate below threshold. |
| 4 | **No dictionary/pattern rejection** — the `while True` loop only checks character classes, so `Password1!` and `qwerty123` pass. | H/M | `PasswordGeneratorPanel.qml:43-49` | Reject against a bundled common-password list + keyboard walks/sequences before printing. |
| 5 | **No sunrise/sunset or tithi end times** — a Panchang's core utility is *when* a tithi/nakshatra changes; the helper hardcodes `06:00`/`18:00`. | H/M | `astronomy.py:2350-2353`; absent from `compute_panchang:248-315` | Compute rise/set and tithi/nak transition instants for the entered lat/lon; show countdown. |
| 6 | **No dasha/antardasha** — `vimshottari_dasha`, `antardasha`, `full_dasha` exist but no bridge command reaches them (`timelords` calls `time_lords`, not dasha). | H/M | `bridge/kundali.py:68-185`, `133-145`; `astronomy.py:316,661,697` | Add `dasha` command + a timeline view of mahadasha/antardasha periods. |
| 7 | **No muhurta selection** — `muhurta_score()` (purpose-weighted, 50-point scale) has no CLI path and no UI. | H/M | `astronomy.py:1680`; command list `kundali.py:68-185` | Add `muhurta` command; let user pick purpose + date range and list top scored windows. |
| 8 | **No clock-drift correction** — codes come from raw `time.time()`/`Date.now()`; a fast/slow system clock silently yields wrong codes. | H/M | `otp.py:60-67,178`; `AuthenticatorWindow.qml:41,152` | Store a per-entry `offset` and add a "my code differs" wizard that solves for it (as Aegis/Google do). |
| 9 | **Passphrase wordlist is an uncurated system dictionary** — `/usr/share/dict/words`, lowercase-alpha 4–8 chars, English-only, fixed `-` separator, word count `max(4, n//5)`. | M/H | `PasswordGeneratorPanel.qml:37-41` | Ship a small curated diceware list (EN + one Indic), add separator/capitalization/number options. |
| 10 | **No history or favorites** — every refresh or option change overwrites the single `generated` string; a accidentally-lost good password is unrecoverable. | M/H | `PasswordGeneratorPanel.qml:54,125,90-93` | Keep a short in-memory list of recent candidates with a "keep" star (never persist secrets). |
| 11 | **Vikram Samvat only approximated as a year** — `year + 57`, no Samvat month/day, and not displayed at all; wrong before Chaitra. | M/M | `astronomy.py:286-300`; `KundaliPanel.qml:131-136` | Convert the date into Vikram Samvat month/paksha/tithi using the computed `masa`, show alongside Gregorian. |
| 12 | **YubiKey OATH handling is shallow** — every key credential is forced to period 30 / digits = code length; HOTP credentials are skipped; no add/delete/rename on the key. | M/M | `otp.py:224`, `271-272`, `282-284` | Parse `ykman oath accounts list` for real period/digits/type; expose credential management via `ykman oath accounts add/delete`. |
| 13 | **No horoscope matching / gun milan** — the only two-chart helper is `synastry()` (cross-aspects), not 36-point Vivaha Milan; no two-birth input anywhere. | M/M | `astronomy.py:776-791`; `bridge/kundali.py:68-185`; `KundaliPanel.qml:67-89` | Add `match` command computing the 36 gunas + mangal/raj yoga flags; two birth forms side by side. |
| 14 | **No planet→house mapping or divisional charts** — planets and houses are printed as two unrelated lists; varga helpers (`_dashamsha`, `_dwadashamsha`, `all_vargas`) are unreachable. | M/M | `KundaliPanel.qml:138-145`; `astronomy.py:431-465,~800` | Annotate each planet with its house/lord and add a Navamsha table. |
| 15 | **No Steam Guard format** — Steam uses `steamauth://` and a custom base-32 alphabet with a 5-character symbol set; `parse()` only accepts `otpauth://totp/` and standard base32. | M/M | `otp.py:73-76`, `48-57` | Add a `steam` scheme with Steam's alphabet and 5-char encoding (separate code renderer, not `totp()`'s digits). |
| 16 | **No camera QR scan** — "Scan a QR code on the screen" only grabs a screen region via `slurp`+`grim`+`zbarimg`; no webcam/v4l path for a code shown on a phone. | M/M | `otp.py:206-220`; `AuthenticatorWindow.qml:108` | Add a camera capture button (PipeWire portal or `ffmpeg -f v4l2`) feeding the same zbar decode. |
| 17 | **No single-use backup/recovery-code storage** — the keyring schema stores only TOTP secrets; services hand out 8–10 one-time codes that are discarded after use. | M/M | `otp.py:121-129`, `155-169` | Add a `backup` item type: list of codes, mark-used-on-copy, stored in the same Secret Service item. |
| 18 | **No auspicious-time reminders** — Panchang is computed only on demand; there is no "warn me when Brahma Muhurta / Rahu Kalam starts" or Calendar handoff. | M/L | `KundaliPanel.qml:30-46,91-96` | Compute next window and fire a notification / create a Calendar event via existing shell services. |
| 19 | **No auto-fill handoff** — generated secrets go only to the clipboard; the keyring is opened separately as a read-only GPG list, so nothing links generation to a saved login. | M/L | `PasswordGeneratorPanel.qml:56-60`, `180-188` | Offer "save to keyring" via `passwords.py add` and/or a browser autofill D-Bus handoff. |

**Skipped:** pronounceable/syllable passwords and North/South Indian chart styles — lower value than the 19 above; no runtime verification (static only). **Risk:** `shani-chronoa`'s dasha/muhurta/varga helpers are visibly simplified (`sunrise_approx = "06:00"`, "approximate" Samvat), so wiring #1/#6/#7/#11 into the UI will expose rough values as if authoritative — label them "approximate" until the astronomy is cross-checked.

---

# Eleventh pass — VERBATIM agent reports

## VERBATIM: Diagnostic tools depth

I read both GAPS docs in full and audited the interactive-diagnostics surfaces. I excluded the exact items already filed (Logs' raw-entry button / unused `priColor` / severity-unit-boot filters / `-n 200` / export / PRIORITY search / new-error notice; process details dialog, signals, renice, Users view, sort, PSI; health "text-only/no remediation" and "two divergent systems"; system-report crash specifics; SMART, thermal, SysStats meters; shani-doctor).

## Ranked gaps — value × ease

**Tier 1 — high value, cheap**

1. **[H/E] Health ring ignores failed *user* units.** `health-check.py:52` runs `systemctl --failed` with no `--user`, so a failed `shani-*` bridge/user service leaves the ring green while the desktop is half-dead. Sketch: add a `--user` check (shani-health checks both scopes).
2. **[H/E] Disk column is a lifetime total, not a rate.** `Processes.qml:377,453` + `TopProcesses.qml:156-178` read `/proc/<pid>/io` cumulatively; you cannot see which process is hammering disk *now*, and read/write are merged. Sketch: keep previous `io` sample and show Δbytes/s, split read vs write (iotop's core view).
3. **[H/E] Follow mode yanks the reader back to newest.** `LogsPanel.qml:84-89` re-runs `readJournal()` every 3 s and `:116` replaces the whole model, so scrolling back or selecting a row is discarded and there is no "pause while scrolled". Sketch: stop the timer while `list.contentY > 0`; add a "Jump to latest" pill (GNOME Logs behaviour).
4. **[H/E] Problem report has no redaction controls.** `system-report.py:57` is only a prose warning; `:51,65` include the hostname verbatim, `:90` dumps `lspci -nn`, `:104-135` dump 200 journal lines with possible usernames/IPs. `shani-health --export-logs` (shani-health.md:213-219) *filters secrets*. Sketch: opt-in scrub of host/user/IP/MAC fields before opening the editor.
5. **[H/E] No time-range window in Logs.** `LogsPanel.qml:80` is count-based (`-n 200`) only; "what happened 14:00–15:00 yesterday" or an older boot is unreachable. Sketch: `--since/--until` + boot-ID picker.
6. **[M/E] Health is a one-shot snapshot with no trend.** `SettingsAbout.qml:21-23` runs the check only while About is open; `:54-58` keeps just the latest JSON. Sketch: append each result to a small log and draw a score sparkline (Reliability Monitor's timeline).
7. **[M/E] Category chips are regex heuristics, not journal sources.** `LogsPanel.qml:40-54,148` classify one merged stream, so "Kernel"/"User" can misclassify; audit logs are never read anywhere in the tree. Sketch: map chips to `-k` / `--user` / `-u UNIT` / `--file=/var/log/audit/audit.log`.
8. **[M/E] No bookmarks on log entries.** `LogsPanel.qml:30` holds only `selected`, erased by every 3 s refresh. Sketch: cursor-keyed bookmark set with a "Bookmarked" chip.
9. **[M/E] Search is literal substring only.** `LogsPanel.qml:68-72` uses lowercase `indexOf`; footer `:267` reports `shown.length` though only 100 are rendered. Sketch: regex toggle + `unit:foo` field operator, and report the rendered count.

**Tier 2 — real work, still worth it**

10. **[H/M] Per-process network is a dead placeholder.** `TopProcesses.qml:123,130` only probes `nethogs` availability; `Processes.qml:252-259` renders "available / not installed" and never launches it. No `ss`, `netstat`, `lsof` or `/proc/net/tcp` reader exists in the tree. Sketch: parse `/proc/net/tcp*` + `/proc/<pid>/fd` into a connections/ports table (Resource Monitor).
11. **[M/M] Shell never surfaces `shani-health`.** `SettingsAbout.qml:54` calls the 4-check `health-check.py`; `:184-187` hands off to Cassini. The CLI's `--journal`, `--export-logs`, `--verify`, `--storage-info`, `--json` (shani-health.md:20-47) are unreachable from the GUI. Sketch: a "Full diagnostics" button showing filtered shani-health output.
12. **[M/E] Graph history is ~3 minutes and memory-only.** `SysStats.qml:21-24,28` caps 60 samples at 3 s; `Processes.qml:136` claims "the last minute" (wrong). Sketch: downsampling ring buffer + on-disk append for hour/day graphs.
13. **[M/M] Per-core is instantaneous bars only; GPU is one nvidia-smi line.** `SysStats.qml:218-238` has no per-core history; `Gpu.qml:82-92` takes the first line of name/util/memory only — no temp/power/clock/fan, no `rocm-smi`/Intel, no per-process GPU. Sketch: extend the query fields and store per-core sparklines.
14. **[M/M] Threads are a count, not a view.** `TopProcesses.qml:117` and `Processes.qml:478` show `Threads: N` only; no TID list, state or per-thread CPU (htop's `H`). Sketch: read `/proc/<pid>/task/*/stat` into a second ListView.
15. **[M/M] Benchmark coverage is thin.** Only `disks.py:277-305` — a 64 MiB read-only sequential sample, rendered as one line (`DisksWindow.qml:497-498`), no graph; no write/random/queue depth, and no CPU or network benchmark exists (speed test was removed, GAPS.md:216). Sketch: multi-size read/write graph; gate CPU/network benchmarks behind installed tools.
16. **[L/E] Health scoring is unweighted and untunable.** `health-check.py:16,31-90` gives a missing `notify-send` the same weight as 0 GB free, with a hardcoded 2 GB threshold and no warning band. Sketch: per-check severity and a tuneable threshold.
17. **[L/E] Report has no structured or selectable form.** `system-report.py:38-138` always emits the same 7 sections as text; no `--json`, no section checkboxes. Sketch: section flags + JSON output mirroring shani-health.
18. **[L/E] Log details expose structured fields only as raw JSON.** `LogsPanel.qml:247-255` dumps `JSON.stringify(raw)`; `_TRANSPORT`, `_BOOT_ID`, `CODE_FILE/LINE` are unlabelled and uncopyable individually. Sketch: small key/value table with copy-per-field.

**Comparison:** GNOME Logs has real journal sources, severity/time filters and export; htop/btop/iotop/nethogs give live I/O rates, threads and per-process network; Windows Resource Monitor shows TCP connections and Reliability Monitor a timeline. Shani's three tools are quick viewers — fixed buffer, 3-minute in-memory history, one-shot health ring.

Skipped: I did not re-file any of the ten-pass items listed above, and made no edits. Risk: all verdicts are from static reading — no QML runtime, real journald/PipeWire/nvidia-smi or hardware was available, so the misclassification and scroll-reset claims should be confirmed in a live session.

## VERBATIM: Backup/restore edge cases

# Eleventh pass — per-app DATA PORTABILITY (format-level) audit — see pass 11 data portability section

[Backup edge cases report merged — see the backup verification findings in pass 11 curated section; verbatim below:]

1. **H/H — No `restic check` anywhere.** Integrity is inferred from a single-file restore (`restic.py:194-273`, `cli.py:215`); the docs separately tell users to run `restic check`, `--read-data`, and "verify after prune" by hand (`shani-docs/docs/system/backup.md:228,257,364`). No repository-wide verification ever runs. Sketch: add `shani-backup verify` → `restic check [--read-data]`, run after `thin()`, store result in `restore-test.json` alongside the existing restore test.
2. **H/H — Restore-test failure never fails the backup.** `cli.py:217-220` exits on `result.ok` alone and merely *prints* the test result; `backups_page.py:270` discards `restore_test()`'s return; `Backup.qml:110-116` notifies only on job exit code. Sketch: fold `tested.ok` into exit status and both UI notifications.
3. **H/H — Partial backup reported as success.** `restic.py:146-149` treats restic exit 3 ("some files could not be read") as OK; `summary.files_error` is parsed away at `:142-143`. Sketch: include `files_error` count in `Result.detail`/JSON and warn.
4. **M/H — Restore test has false negatives.** `restic.py:247-250` only considers files `0 < size ≤ 50MB`; a backup of empty files or one large file reports "no file to test a restore with" though it may be fine. Sketch: fall back to any file, or to `restic check`, when the size filter finds nothing.
5. **H/M — No space preflight, no cleanup after a failed restore.** `restic.py:183-191` has `timeout=None`, no `df` check against snapshot size; on ENOSPC/drive-loss, `backups_page.py:301-311` leaves a partial tree and the next attempt just picks `Backup of … (2)` (`:284-287`). Sketch: compare free space to `snap.size` first; delete the partial target in a `finally` and write a `.incomplete` marker with a retry/clean action.
6. **M/H — Full restores never verify.** Only `restore_test` passes `--verify` (`restic.py:258-259`); GUI `restic.restore` (`backups_page.py:302`) does not, so bytes written to a bad target are unchecked. Sketch: add `--verify` to `restore()`.
7. **H/M — Local snapshot restores lose fidelity.** `home_page.py:79-86` uses `shutil.copy2/copytree`: no xattrs (SELinux/user.*), no hardlink preservation, sparse files become fully allocated, FIFOs/sockets error or block. Sketch: use `cp -a --reflink=auto` or `rsync -aHAX` for all restores.
8. **M/H — No post-restore verification of local copies.** `home_page.py:387-393` catches only `OSError`; no size/stat/hash recheck. Sketch: compare `st_size` after `restore()` and fail loudly.
9. **M/H — Defaults leave Downloads and mounted filesystems.** `restic.py:42-47` excludes only caches/Trash/.snapshots/CACHEDIR.TAG/.nobackup; no `--one-file-system`, so an under-home mount or loop image is traversed. Sketch: add `--one-file-system` and a Downloads opt-out.
10. **M/M — No user paths or pattern syntax.** Exclusions are a fixed code list; `backups_page.py:98-101` describes only defaults. Sketch: a GSettings exclusion list rendered as `--exclude <pattern>` with restic pattern help.
11. **M/M — No key management or recovery material.** Password lives only in the keyring (`restic.py:91-117`); the UI says "write it down somewhere safe" (`backups_page.py:212-215`), but there is no `restic key add/change/list` flow, and home snapshots are plain ACL'd subvolumes (`home.py:37-46`). Sketch: "Add/change backup password" using `restic key add/remove` and an exportable key file.
12. **H/L — No remote backend at all.** `backups_page.py:195-208` uses a folder picker and rejects paths under home; `config.py:269-275` requires an absolute path; credentials are only ambient env. S3/SSH/B2 URLs cannot be configured. Sketch: URL field + credential inputs mapped to `RESTIC_REPOSITORY`/AWS/SSH env, keyring-stored.
13. **H/H — Manual backups never prune; prune failure ignored.** `cli.py:212-213` calls `thin()` only with `--scheduled` and drops its `Result`; `Backup.qml:108` and `backups_page.py:268` call `backup` without it. A manual-only user's repo grows forever. Sketch: prune after every successful backup and surface its failure.
14. **M/H — No prune preview.** `restic.py:152-156` hardcodes `forget --prune` with fixed `KEEP`; no `--dry-run`, and the docs' verify-after-prune step is manual. Sketch: `backups --prune-preview` → `restic forget --dry-run`.
15. **H/M — Missed catch-up run fails silently.** The restic timer is `Persistent=true`, but its service has no `RequiresMountsFor` or retry (`shani-backup-restic.service`); if the drive isn't attached at that boot, `restic.py:127-128` returns an error once and the day is lost. Sketch: `OnFailure=` notification + retry timer.
16. **M/H — Two conflicting schedule stores.** `config.py` GSettings keys (`schedule-time` default 02:00, `enable-scheduler`) are dead (see `cli.py:326-327`); the real timer uses a drop-in defaulting to 12:30 (`restic.py:298`). Sketch: remove the dead schema keys or make them authoritative.
17. **M/M — Linger and home-snapshot time are unfixable in UI.** The timer is a user unit: it never fires without a session/linger — Cassini only explains this (`backup.py:155-170`). Home snapshots are fixed at `OnCalendar=daily` (`shani-backup-home.timer:7`). Sketch: offer an enable-linger button and a time drop-in for the home timer.
18. **H/M — No proactive backup notifications.** Only the manual job notifies (`Backup.qml:110-117`); the drive banner is app-internal (`backups_page.py:43,138`), staleness (≥3 days, `:142`) is visible only when a page is opened, and the timer units have no `OnFailure=`. No low-disk or drive-not-connected reminder. Sketch: timer `OnFailure=` notify + a session-start staleness/disk/daily reminder.
19. **H/H — Local-snapshot restore gated on an external drive.** `BackupPanel.qml:106,116` sets `enabled: Backup.driveSetUp` (restic repo configured), but the timeline comes from `home list` local snapshots (`Backup.qml:69`). With daily snapshots but no backup drive, every restore button is dead. Sketch: drop the `driveSetUp` gate.
20. **M/H — Sizes always zero and selected snapshot lost.** `Backup.qml:82` reads `s.total_size`, which `home list --json` never returns (`home.py:268-296`), so `formatBytes` is never used; `Backup.qml:37-44` ignores `name` and opens `home` for both "Restore" and "Files only". Sketch: add a size to `Snapshot` or remove the field; pass the chosen snapshot id to the GUI.

**Skipped/not checked:** no runtime or real-slot execution (static only), and I did not re-litigate GAPS.md's listed items. Risk: several findings depend on restic's exact exit-3/`--verify`/`copy2` semantics; confirm against the shipped restic version before implementing.

---

# Tenth pass — VERBATIM agent reports

## VERBATIM: Advanced text editor features

**Method:** static only. Read `docs/GAPS.md`, `docs/GAPS-RESEARCH.md`, then `Modules/TextEditor/TextEditorPanel.qml`, `Services/TextDocs.qml`, `Services/TextMate.qml`, `Common/Highlight.js`, `Common/TextMate.js`, `Common/HighlightText.qml`, `bridge/textmate.py`, `Services/Terminal.qml`, plus greps over `shani/` and `bridge/`.

**Correction to the older docs:** the editor is well ahead of what GAPS.md claims — session restore, multi-caret, snippets, TextMate theme chooser, bookmarks, go-to-line, current-line/matching-brace highlight, word count and regex find all exist in code. Those are the user's skip-list and are not reported below. The real frontier is code intelligence and project/IDE workflow.

## A. Feasible in QML (or a small bridge) — ranked by value × ease

1. **Jump to matching bracket** — `matchBrace()` is fully implemented (`TextEditorPanel.qml:371-391`) and used only to draw a box (`:674-684`); no key ever moves the cursor there. Sketch: add `Ctrl+]` in `shortcut()` (`:430-449`) calling `edit.cursorPosition = win.matchBrace(...)`. Highest ease.
2. **Auto-save to disk** — `setText()` keeps every keystroke in memory only (`TextDocs.qml:199-215`); `save()` is manual (`:243-256`); no `autoSave` setting exists (`Common/Settings.qml:270-274`). Sketch: a `Timer` in `TextDocs` calling `save()` after N seconds of inactivity, with an on/off + delay row.
3. **Unsaved-buffer recovery across restart** — `saveSession()` writes only `{paths, active}` (`TextDocs.qml:79-83`), and `restoreSession()` re-reads files from disk (`:84-101`). Unsaved text is lost on shell restart despite the header comment at `:4-9`. Sketch: include each doc's `text`/`eol`/`modified` in the session JSON and offer "Recover".
4. **EOL selector** — EOL is *detected* and preserved (`TextDocs.qml:189`) and reapplied on save (`:254`), but the user cannot choose LF/CRLF. Sketch: a status-bar chip cycling `d.eol` before `save()`.
5. **Type-over closing bracket** — `handleAutoclose()` inserts pairs and deletes pairs on Backspace (`TextEditorPanel.qml:89-124`) but typing `)` next to an auto-inserted `)` produces `))`. Sketch: if the next char equals `closeOf(c)`, advance the cursor instead of inserting.
6. **Soft-wrap modes** — `wordWrap` is one boolean (`TextEditorPanel.qml:46`, `:720`). No off / wrap-at-viewport / wrap-at-column (80), no wrapped-line gutter marker. Sketch: a 3-state toggle driving `wrapMode` + a column ruler.
7. **External-change / conflict detection** — the file is probed only at open (`TextDocs.qml:142-145`); there is no watcher, no mtime check, no "changed on disk" banner. A second editor can overwrite silently. Sketch: `DirMonitor`/periodic `stat` comparing mtime, then a Reload/Discard banner.
8. **Breadcrumbs (cursor path)** — status bar shows path + line/column only (`TextEditorPanel.qml:778-808`). Sketch: regex-scan braces/`function|class|def` above the cursor and render `file › class › fn › line` in the tab strip.
9. **Format document** — the editor panel spawns no process at all (no `Process`/`execDetached` in the file). Sketch: one bridge command dispatching `black`/`rustfmt`/`prettier`/`clang-format` by `win.lang`, replacing text via `TextDocs.setText()`; tools are optional deps, so degrade with a message.
10. **Git status / diff for the open file** — `/usr/bin/git` exists, but no editor code calls it. Sketch: a side pane with `git diff -- <path>` rendered through the existing `diff` highlighter (`Highlight.js:34,111`).
11. **Open a folder → file tree → project search** — `TextDocs.open()` explicitly refuses directories (`TextDocs.qml:143,169`), so the editor is single-file only; find/replace is per-document (`TextEditorPanel.qml:334-354,410-428`). Sketch: reuse `Services/Files` listing in a left panel and a `grep -rn` bridge for "Find in files".
12. **Code folding** — the gutter holds only line numbers and bookmark dots (`TextEditorPanel.qml:625-650`). Sketch: compute indent/brace ranges and elide those line ranges in *both* overlay TextEdits (`:700-714` and `:715-763`), with a gutter chevron.
13. **Selection grow/shrink** — Alt+Shift+Down/Up adds *vertical* cursors (`TextEditorPanel.qml:164-169,743-746`); there is no structural "expand selection to word → string → block". Sketch: brace/quote scan around selectionStart/End, mirroring `matchBrace()`.
14. **Sticky scroll** — `flick.follow()` scrolls everything (`TextEditorPanel.qml:659-664`); no pinned enclosing scope header. Sketch: reuse the breadcrumb scan from #8 as a 1-line overlay that persists while scrolling.
15. **Encoding selector** — the probe rejects any NUL-bearing file with `grep -qI ""` (`TextDocs.qml:143`), so UTF-16/32 is "Not a text file" (`:169`); `FileView` uses its default codec (`:179-196`). Sketch: bridge sniff of BOMs, explicit codec in a decode helper, and a UTF-8/Latin-1/UTF-16 chip.
16. **Minimap** — the Flickable contains only the two TextEdits and highlight overlays (`TextEditorPanel.qml:651-775`). Sketch: render the `paint` text at 1:5 scale into a narrow column and map `contentY`. Low value per effort.
17. **TextMate grammar data** — the loader scans two dirs (`TextMate.qml:16-19`) and highlights via `TextMate.js`, but **0** `.tmLanguage`/`.tmTheme` files ship outside Flatpak caches; every file falls back to keyword regex (`Common/Highlight.js:8-45`). Sketch: vendor five small grammars (C/Py/QML/JS/JSON). Overlaps an earlier file-format finding.

## B. Needs an LSP daemon (or comparable backend)

Grep for `lsp`, `language server`, `textDocument/*`, `publishDiagnostics`, `semanticTokens`, `completion`, `definition`, `rename`, `hover` across `shani/` and `bridge/` returns **zero** matches. The editor imports only `Highlight.js` (`TextEditorPanel.qml:17`) and launches no language process.

18. **LSP client core** — no JSON-RPC transport, no workspace/rootUri, no capability handshake. Needs a bridge speaking stdio JSON-RPC and a QML-facing singleton. Sketch: `bridge/lsp.py` + `Services/Lsp.qml` mapping requests to document URIs.
19. **Completion / IntelliSense** — the only "completion" is seven hard-coded Tab snippets (`TextEditorPanel.qml:61-87,756-758`). Needs `textDocument/completion` + a popup delegate; no QML-only fix gives real symbols.
20. **Diagnostics / problems list** — no squiggles and no problems panel; the only error surface is `TextDocs.error` (`:30`, status bar `:784`). Needs `publishDiagnostics`; a cheap QML-only subset is `python -m py_compile`-style lint, but that is not diagnostics.
21. **Go-to-definition / find references** — only go-to-*line* (`:269-276,360-370`). Needs `definition`/`references` plus a results list.
22. **Rename symbol across files** — find/replace touches the current buffer only (`:410-428`). Needs `workspace/applyEdit`; the atomic multi-file save path would have to be newly written.
23. **Hover docs / signature help** — no hover handler anywhere near the editing surface. Needs `hover`/`signatureHelp` and a rich-text tooltip.
24. **Embedded terminal, build/run tasks, problem list** — `Services/Terminal.qml:1-52` only picks an *external* emulator (foot/Ghostty/kitty); the editor has no Run action. A "run file in terminal" is QML-feasible by launching the chosen terminal; a true embedded terminal and a build-task/problems pipeline need a PTY bridge and an LSP/task daemon.
25. **Collaboration / CRDT** — grep for `CRDT`, `yjs`, `automerge`, `collab` is empty; documents are plain in-memory strings (`TextDocs.qml:23-26`). Needs a transport and server; out of scope for a local shell editor.

**Top five by value × ease:** #1, #2, #3, #4, #5 — all small, self-contained changes in `TextEditorPanel.qml`/`TextDocs.qml`.

Skipped: runtime/QML verification (static only), third-party LSP availability on the image, and any upstream comparison against actual Kate/Helix binaries. Risk: the line numbers are from the current tree and the session/TextMate code is newer than the docs, so anything already filed as "open" in GAPS.md for the editor should be re-checked against source before being re-reported.

## VERBATIM: Advanced email composition

# Tenth-pass deep gaps — Advanced Mail composition & organization

**Verdict:** Mail is a four-pane reader with a single plain-text compose box. Every item below is *new at this depth* — composition metadata, organization, integration, and send lifecycle are absent from both the bridge command vocabulary (`mail.py:20-33,689-900`) and the QML surface (`MailWindow.qml`). Ranked by value × ease.

## Composition

1. **Recipient autocomplete from Contacts** — `MailWindow.qml:353-355` To/Cc/Bcc are bare `TextField`s; `Contacts.qml:16` already holds `{name,email,avatar}` but Mail never reads it. Sketch: `Repeater` over `Contacts.contacts` filtered on prefix → popup, fill `toBox`. *Cheapest high-value win in the app.*
2. **Per-account signature** — `mail.py:11-15` config has no signature field; `send()` at `mail.py:648-655` sets only From/To/Cc/Subject/Date; `MailWindow.qml:360` body starts empty. Sketch: `account.signature` in `mail.json`, append in `send()`, one Settings row.
3. **Request a read receipt** — `mail.py:648-655` emits no `Disposition-Notification-To`; no toggle exists. Sketch: checkbox in compose → `msg["Disposition-Notification-To"] = From`.
4. **Delivery priority / importance** — `mail.py:648-655` sets no `X-Priority`/`Importance`. Sketch: High/Normal/Low combo → two headers.
5. **"Do not reply" / Reply-To override** — `send()` (`mail.py:648-655`) never sets `Reply-To`; no field. Sketch: optional `replyTo` field → `msg["Reply-To"]`, or a no-reply `From`.
6. **Send later / schedule** — `send()` transmits immediately (`mail.py:643-686`); no timer or queue anywhere. Sketch: datetime picker → local pending-jobs file + `systemd-run --on-calendar`, or a QML `Timer`.
7. **HTML / rich-text compose** — `MailWindow.qml:360` fixes `textFormat: Text.PlainText`; `mail.py:655` uses `set_content(body)` only, no alternative part. Sketch: RichText TextArea + `msg.add_alternative(html, subtype="html")`; sanitize on send.
8. **Spellcheck in compose** — `MailWindow.qml:360` `TextArea` has no spelling support; global "no spellcheck" note (`GAPS.md:1561`) never scoped to Mail. Sketch: Qt 6 `TextArea` spellcheck hints + dictionary at `Mail.qml`.

## Attachments (outbound)

9. **Drag files into compose** — `MailWindow.qml:335-380` compose is a plain `Rectangle` with no `DropArea` (save-side picker at `:20-26` is unrelated; `GAPS.md:1367`). Sketch: `DropArea` accepting `text/uri-list` → attachment chip row passed to `send()`.
10. **Attachment preview / open** — `MailWindow.qml:248-264` shows name/type/size plus a save button only; `mail.py:197-219` decodes bytes but never renders. Sketch: "Preview" → QuickLook handoff or temp-file `Qt.openUrlExternally`.
11. **Inline/CID images** — `mail.py:155` replaces every `<img>` with `[image]`; `bodies_of()` (`mail.py:164-179`) never resolves `cid:` parts. Sketch: map `cid:` → saved MIME part → `TextDocument` image source.
12. **Large-file handling / attach-as-link** — `send()` (`mail.py:643`) has no size check or link alternative. Sketch: threshold warning + upload/link (needs storage backend).

## Organization

13. **Message filters / rules on arrival** — `mail.py:20-33` command set has no rule engine; only manual `imap_move` (`:547-560`). Sketch: `filters.json` + apply in `imap_list`/`imap_read` (move/flag by sender/subject).
14. **Quick filters (unread-only, etc.)** — `MailWindow.qml:127-144` list has no filter controls despite `folders[].unread` (`Mail.qml:16`). Sketch: All/Unread/Starred chips in the list header.
15. **Saved searches** — `Mail.search()` (`Mail.qml:63`) sets transient `query` only; nothing persists. Sketch: store named queries in the folder pane, one click to re-run.
16. **Snooze until** — no `snooze` command (`mail.py:20-33,689-900`); `Mail.qml:42-63` has none. Sketch: `snooze <uid> <iso>` → hide + flag, local timer unflags at time.
17. **Tags with colors / pin important** — only IMAP `\Flagged` star (`Mail.qml:49`, `mail.py:534`); list sorts by date only (`mail.py:438`). Sketch: custom IMAP keywords + color map, pinned section above the list.

## Conversation view

18. **Quote collapsing + load older** — `MailWindow.qml:331-334` flattens the quote into one `>`-prefixed block with no toggle; `imap_list` hardcodes last 100 (`:438`) and `Mail.open()` (`:44`) just re-lists. Sketch: fenced collapsible quote region and an "Load older" footer with `list <folder> <offset>`.

## Contacts / calendar integration

19. **Add sender to Contacts / contact photos** — reader renders `Mail.from` as plain Text (`MailWindow.qml:191-198`); no `Contacts.add()` call. Sketch: avatar + "Add to Contacts" passing parsed `sender()` (`mail.py:232-239`).
20. **RSVP buttons / meeting indicators in the message** — `imap_read`/`mh_read` (`mail.py:503-526,293-331`) ignore `text/calendar` parts; `safe_html()` strips them. Sketch: parse the calendar part → Accept/Tentative/Decline + iTIP REPLY (distinct from the Calendar-side S11 gap).
21. **Convert email to event** — no Agenda/Calendar reference in `MailWindow.qml`; Sketch: "Create event" button handing subject/date/body to the existing Agenda add path.

## Send lifecycle & keyboard

22. **Undo send / outbox / failed-send retry** — `MailWindow.qml:369-374` closes compose immediately; on error `Mail.qml:138-139` only sets `note`, no persistence. Sketch: 5s grace + Undo toast; failed sends to `outbox.json` with Retry.
23. **Draft autosave across restarts** — Cancel clears all fields (`MailWindow.qml:377`), compose is memory-only. Sketch: write compose fields to XDG state on `textChanged`, restore on open.
24. **Full keyboard navigation + compose-in-new-window** — only `onAccepted` on search (`MailWindow.qml:81`); no `Keys.onPressed`, no pane `KeyNavigation`; compose is a centered modal (`:335-345`). Sketch: j/k/r/c// keys + a standalone compose `AppWindow`.

**Skipped / not checked:** message templates (already noted) and all items in the parent skip list; no runtime, Qt-version, or live-IMAP verification — purely static. **Risk:** #7/#11 depend on Qt's HTML subset and CID support in this image; #20's iTIP REPLY needs the Calendar backend's attendee path, which is itself noted as incomplete (`GAPS-RESEARCH.md:832`).


---

# Ninth pass — VERBATIM agent reports

## VERBATIM: Crash handling, diagnostics and self-recovery

# Ninth-pass research — crash handling, diagnostics and self-recovery of the shell itself

Read both docs (2,657 lines) first. Skipped all prior-pass topics (niri crash recovery, session lifecycle, audit trail, problem reports, logs panel, shani-doctor, health checks) — the items below are crash/diagnostics/self-recovery only. Static analysis, nothing run or edited.

## Ranked gaps (value × ease)

1. **Mid-conversation bridge death spins forever.** `Services/Chronoa.qml:135-139` — `onConnectedChanged` sets only `state="offline"`; `busy`, `step`, `approval` are never cleared, and no turn timeout exists anywhere. `Island.qml:30,80,152` keys the "working" spinner off `Chronoa.busy`. Sketch: on disconnect clear busy/step, emit `system("Chronoa stopped responding")`, open panel; add 60s turn watchdog.

2. **Bridge never detects Chronoa D-Bus death.** `bridge/chronoa-bridge.py:389-412` subscribes to `Agent.Event` but has no `NameOwnerChanged` watch and no turn timeout; `turn_filter` waits for a `done` that never arrives. Sketch: watch `AGENT_NAME` owner loss, broadcast an `error` event, plus per-turn timeout.

3. **Persistent QML bridges die silently.** `Services/Plugged.qml:248-255`, `InputPlumber.qml:122-126`, `Modem.qml:46-50`, `Thunderbolt.qml:28-31` are `running: true` Processes with no `onExited` restart — Quickshell does not auto-restart. Only `LauncherEntries.qml:39-41` retries (blindly) and `Files.qml:150-195` has a real watchdog. Sketch: one shared bridge wrapper with retry+backoff.

4. **No watchdog for a hung shell.** `data/systemd/shani-shell.service:21-22` is `Restart=on-failure` only; no `WatchdogSec`, no `sd_notify`. A frozen event loop is a dead desktop that systemd never touches. Sketch: `WatchdogSec=30` + QML keepalive timer.

5. **Crash loop ends in a failed unit with no UX.** `RestartSec=2` plus systemd's default `StartLimitBurst=5/10s` trips after ~5 crashes; no `StartLimitAction`, no notice. Sketch: back off longer and add an on-failure oneshot that notifies "Desktop stopped, see report".

6. **No user notification for any bridge restart.** `Bridge.qml:37-42` reconnects silently; `LauncherEntries.qml:39-41` retries silently. Sketch: notify after 3 rapid restarts, name the service, offer Retry/Report.

7. **No failure counting / self-diagnosis.** Zero `NRestarts`/`RestartCount` reads in the tree; `bridge/health-check.py:43-97` has only space/failed-units/writable/tools checks. Sketch: add a check reading `systemctl show -p NRestarts shani-chronoa-bridge` and per-bridge counters.

8. **Unsaved editor content lost on crash.** `Services/TextDocs.qml:42-86` persists only open *paths* in `text-editor-session.json`; buffers are memory-only. Sketch: autosave dirty buffers to XDG state every 30s, offer restore at next start.

9. **No "desktop restarted" signal.** Nothing records an abnormal previous exit. Sketch: clean-shutdown marker; if absent at start, toast + open diagnostics.

10. **No crash dumps.** No coredump config anywhere; a Quickshell segfault leaves no backtrace. Sketch: enable systemd-coredump and list it in the report.

11. **Problem report lacks crash specifics.** `bridge/system-report.py:100-140` has journald errors (this + previous boot) and failed units, but no per-bridge unit logs, restart counts, or coredumps. Sketch: add a "Crashes" section (`journalctl -u shani-chronoa-bridge`, `coredumpctl list`).

12. **No automated or crash-triggered reporting.** The report is a manual button in `Modules/Settings/SettingsAbout.qml:59-75`; nothing sends or prompts after a crash. Sketch: on abnormal restart offer "Send diagnostics?" behind explicit consent.

13. **Half-dead bridge is invisible.** The bridge implements `ping` (`chronoa-bridge.py:206-207`) but `Bridge.qml` never sends one; a stuck event loop with an open socket looks healthy. Sketch: 30s ping/pong, mark offline on missed pong.

14. **Almost no diagnostic logging.** `Common/Log.qml:46` is the tree's only `console.log`; `Log.scoped` appears only twice in real code (`Services/Files.qml:27`, `Common/Proc.qml:24`). Silent `catch(e){}` at `Bridge.qml:32`, `Plugged.qml:253`, `chronoa-bridge.py:395`. Sketch: route catches through scoped loggers.

15. **Unbounded dev logs / unconfigured journald.** `dev/session.sh:107,116-241` redirects every daemon to `$L/*.log` with no rotation; no `journald.conf` ships with the product. Sketch: logrotate in dev, journald size caps in image.

16. **Socket unlink race on restart.** `chronoa-bridge.py:419-423` unconditionally unlinks the socket; a fast systemd restart with a lingering old process can remove the live socket. Sketch: bind-then-replace, or check owner.

## Comparison (Q7)

GNOME restarts gnome-shell via the session unit and feeds crashes to ABRT/gnome-abrt with a triaged report; KDE's DrKonqi shows a backtrace dialog with "restart application" and bug-report actions; Windows Reliability Monitor gives a chronological crash timeline; macOS Crash Reporter writes per-app `.ips` reports. Shani has restart-on-failure, a manual text report, and none of the dialog, timeline, backtrace, or consented sending.

Skipped: no dynamic reproduction, no systemd/Quickshell internals verified beyond source, no changes made. Main risk: Quickshell's `Process` restart semantics are inferred from `LauncherEntries.qml`'s explicit retry, not confirmed against upstream docs.

## VERBATIM: Multi-monitor display edge cases

# Ninth-pass gap research — multi-monitor & display hotplug edge cases

**Static only.** Skipped per instructions: per-monitor wallpaper/scale, EDID, hotplug workspace-placement restore, arrangement profiles, named monitor targets, swap-monitors limits, fractional scaling. Also skipped: Ruler "grim all outputs" and Magnifier "cross-monitor" (already in GAPS.md capture-tools section) — but the *mixed-scale* angle below is new.

## Shell-fixable (ranked by value × ease)

**S1. Window previews use logical geometry for a physical-pixel capture.** `WindowPreview.qml:27-34` derives the `grim -g` rect from `Displays.outputs` `x/y/width/height` — which are niri's **logical** pixels (`Displays.qml:241-243`) — plus `tile_pos_in_workspace_view`; `grim` expects **physical** pixels. On any scaled output (1x+2x) the rect is half-size/wrong origin. Worse, `Dock.qml:530` passes `Niri.focusedOutput`, not the window's own output, so hovering a dock tile on monitor B for a window on monitor A uses A's origin. *Sketch: multiply rect by that output's scale and pass the window's `output`/`win` workspace output.*

**S2. Ruler's pixel ratio comes from an arbitrary monitor.** `Ruler.qml:37-41` sets `ratio` once from `Displays.outputs[0].scale` (outputs are sorted by connector name, `Displays.qml:232`), while `grim "$1"` (`:63`) captures a **composite of all outputs** and `RulerPanel.qml:27-35` fits that whole composite into the *focused* screen. On mixed scale or portrait+landscape, both the fit and the ratio are wrong. *Sketch: `grim -o <focusedOutput>`, set `ratio` from that same output.*

**S3. A monitor greeted while locked is never greeted after unlock.** `Plugged.qml:72` drops greetings when `Lock.locked` *before* marking `seen`; `onArrived` (`:245`) fires once, and `Displays.known` (`Displays.qml:257-263`) already contains the output, so no replay. Plug a monitor at the lock screen → no Extend/Mirror prompt, ever. *Sketch: queue arrivals while locked, flush on `Lock.unlocked()`.*

**S4. Presenting survives unplugging its source.** `Plugged.qml:164-171` only ends presentation when `presenting.output` (the target) departs; if the mirrored-from monitor is unplugged, `wl-mirror` keeps a dead source while DND and caffeine stay on. *Sketch: also end on source departure, or track source explicitly.*

**S5. Focus-following single surfaces teleport between monitors.** ~30 surfaces bind `screen: find(name===Niri.focusedOutput) || screens[0]` (e.g. `Island.qml:26`, `Osd.qml:213`, `Launcher.qml:32`, `WindowMenu.qml:18`, `shell.qml:203`). A Chronoa approval card, launcher, or control centre open on monitor A jumps to B when focus changes; if the focused output is unplugged, everything falls back to `screens[0]`. *Sketch: sticky output per open surface (capture `Ui.screen` at open, re-anchor only if that output departs).*

**S6. Lid close produces no shell behaviour.** `InputConfig.qml:137-138` forwards lid events; `TabletMode.qml:27-28` only sets `lidClosed`, read by nothing but the test state dump (`shell.qml:1154`). With `HandleLidSwitchExternalPower=ignore` (`shani-admin.py:265`, docked), closing the lid on an external monitor leaves the internal panel logically on, focus untouched, idle unchanged. *Sketch: on lid-close with external outputs, turn off internal output + focus external + re-arm idle.*

**S7. "minimised" is one global workspace name across all outputs.** `Niri.qml:92-94` finds the *first* workspace named `minimised`; `minimise()` (`:96-114`) moves windows there by name. With 2+ outputs, minimising on the non-first monitor moves windows to the other monitor's hidden workspace, and `isMinimised()` then hides them from both bars. *Sketch: keep a per-output hidden workspace (`minimised:<output>`).*

**S8. "Extend" assumes a landscape right-hand neighbour.** `Plugged.qml:180-181` sets `x = max(right edge), y = 0` unconditionally; a portrait monitor beside a landscape one is top-aligned, not centred, and there is no left/above choice. *Sketch: centre on `y`, offer side via setting.*

**S9. Dock layout swaps behind the lock, and only has two states.** `Docking.qml:25-29,41` follows `Displays.outputs` hotplug with no `Lock.locked` guard, so bar/dock/gaps change while locked; all 3+ monitor setups collapse to "docked". *Sketch: defer `follow()` until unlock; key layout by output-set.*

**S10. Per-monitor wallpaper is dropped on the lock screen and overview.** `LockScreen.qml:205` and the overview backdrop `Wallpaper.qml:38` both use the global `Theme.wallpaper`, while the live background honours `wallpapersByMonitor` (`Wallpaper.qml:66-73`). Locked/overview shows one picture on every monitor. *Sketch: use the same `wanted` resolver with the surface's output name.*

**S11. Magnifier shows a stale frame after focus moves.** `Magnifier.qml:18` rebinds `screen` to the focused output, but `grab()` (`:36-48`) runs only on open/right-click; switching monitors keeps the old monitor's frozen frame under the loupe. *Sketch: `onScreenChanged: grab()` and reset `at`.*

**S12. `Quickshell.screens` and `Displays.outputs` desync during hotplug.** Per-output layers are built from `Quickshell.screens` (`Bar.qml:21`, `Wallpaper.qml:20`, `Dock` via `shell.qml:101`) but read geometry from `Displays.outputs` (`Bar.qml:211-212,296`), which lags niri's rescan (`Displays.qml:214-219`). A brand-new output briefly gets a bar/wallpaper with width 0. *Sketch: guard geometry bindings until `Displays.outputs` contains the output.*

## niri / compositor-level (not shell-fixable)

**N1. "Mirror" is a fullscreen `wl-mirror` window, not a cloned output.** `Displays.qml:169-177`, `Plugged.qml:154-161`. It inherits niri's per-output mode/refresh and cannot honour independent VRR; projector mirroring with mixed refresh or resolution is fundamentally limited.

**N2. No audio routing for presentation mode.** `present()` toggles DND/caffeine only (`Plugged.qml:159-160`); nothing routes sound to the projector's HDMI sink. Needs a PipeWire sink choice tied to the output.

**N3. Idle screen-off is all-or-nothing.** `Idle.qml:119` issues `power-off-monitors` globally; no per-output dim/off, so a presentation cannot keep one screen awake.

**N4. Refresh/VRR/scale values are per-output in config only.** `Displays.qml:126-167` writes `mode`/`scale`/`variable-refresh-rate` per output, but niri applies them on reload with no "applied" event — the shell polls 4× over ~4 s (`:211-219`), so mixed-rate/VRR changes can briefly disagree with reality.

**Risk / not checked:** no runtime or multi-monitor hardware available; all findings are static. The highest-value fixes (S1, S2) need a real 1x+2x setup to confirm which coordinate space niri reports in `tile_pos_in_workspace_view` — if niri already reports physical pixels there, only the output-origin term of S1 is wrong.

## VERBATIM: Network protocol depth

I've read all seven passes plus ECOSYSTEM.md and voltkit-alignment.md, and verified candidates against the actual tree (Writing Tools, long-press quick tiles, Live Activities, blur/glass, focus app-allowlist and named-panel ideas are already built or filed — excluded). Here is the eighth-pass report.

[NOTE: the following is the ninth-pass NETWORK PROTOCOL report, filed here verbatim.]

I've read all seven gap files (GAPS.md 1885 lines, GAPS-RESEARCH.md 772 lines), skipped the listed items, and read the six bridges plus Net/Proxy/Updates QML and the deploy downloader. Static only; no runtime/network verification.

# Ninth-pass protocol-level gaps (ranked by value × ease)

## Shell-fixable (bridge/QML change only)

**S1. SMTP uses implicit TLS on STARTTLS port 587.** `bridge/mail.py:631` defaults port 587, `:645-648` defaults `ssl:true` → `SMTP_SSL` (465-style) on a submission port that expects STARTTLS; most providers reject. Sketch: key TLS mode off port (465=SMTP_SSL, 587/25=STARTTLS), fail closed.

**S2. STARTTLS optional → credentials sent in clear.** `mail.py:653-661` calls `s.login()` even when the server has no STARTTLS; `mail.py:381-386` opens plain `IMAP4` (port 143 path) and LOGINs with no STARTTLS at all. Sketch: require `starttls()` for non-loopback hosts, abort if unavailable.

**S3. UID/sequence-number mix makes search results unclickable.** `imap_search:462,466` returns real UIDs via `box.uid(...)`, but `imap_read:493`, `imap_flag:524`, `imap_move:538`, `imap_delete:605`, `imap_source:553`, `imap_attachment_data:567` treat that ID as a *sequence* number via `box.fetch/store`. Acting on a hit can flag the wrong message. Sketch: use `box.uid()` everywhere; keep one ID space.

**S4. Feeds never send conditional GET.** `feeds.py:140-149` sends no `If-None-Match`/`If-Modified-Since`; `refresh_one:254-260` stores no ETag/Last-Modified, so every refresh re-downloads full bodies and 304 handling is impossible. Sketch: persist validators, send them, treat 304 as no-op.

**S5. No OAuth2/XOAUTH2 anywhere.** `password():81-96` returns only `$SHANI_MAIL_PASSWORD`/`secret-tool` plaintext; `:385-386` and `:649-660` use bare LOGIN. Google/Microsoft/modern iCloud accounts are unreachable without an app password. Sketch: add `box.authenticate("XOAUTH2", ...)` and a token source (see D1).

**S6. No DKIM/SPF/DMARC result shown.** `imap_read:503-512` and `mh_read:321-330` return only from/to/subject/date/text — `Authentication-Results` and `Received-SPF` are discarded. Sketch: parse `Authentication-Results` into a `auth` badge field.

**S7. RSS `content:encoded` and full Atom content lost.** `parse_feed:180-186` searches plain/ATOM namespaces, never `http://purl.org/rss/1.0/modules/content/`, so full-text feeds fall back to a short `<description>`. Sketch: add the content namespace to the lookup chain.

**S8. No S/MIME or PGP handling.** `bodies_of:164-179` only walks `text/plain` and `text/html`; `multipart/signed`, `application/pgp-encrypted` and `application/pkcs7-mime` parts are silently ignored. Sketch: detect signed/encrypted parts and either decrypt via gpg or show an explicit "encrypted, unsupported" state.

**S9. Folder LIST parsing assumes `/` delimiter and unescaped names.** `imap_folders:397` splits on the literal `' "/" '`; `:401` quotes with naive `'"%s"' % name`. Servers using `.`, or names containing `"`/`\`, fail. Sketch: parse the LIST tuple properly and use `imaplib`'s quoting.

**S10. Full-message refetch on every list; no cache/UIDVALIDITY/CONDSTORE.** `imap_list:425` does `BODY.PEEK[]` for the last 100 messages per folder on each open; no Maildir cache, no UIDVALIDITY, no CONDSTORE/QRESYNC. Sketch: cache headers+snippets locally, fetch `FLAGS`+header only, track UIDVALIDITY.

**S11. No attendee RSVP roundtrip.** `events:151-152` hardcodes `organizer=""` and `needsAction=False`; `_ical_text:391-420` emits REQUEST/ATTENDEE but nothing reads `PARTSTAT`/`RSVP` or emits an iTIP REPLY. Edits/deletes (`:509-519`, `:506-508`) never bump `SEQUENCE` or send CANCEL/updated REQUEST. Sketch: parse ATTENDEE state, add accept/decline → `METHOD:REPLY`, increment SEQUENCE on edit.

**S12. Webcal subscriptions unsupported.** `account_add:551-598` accepts only `http(s)` WebDAV collections; no `webcal://` and no `SOURCE_EXTENSION_WEBCAL` path. Sketch: accept `webcal:` → `https:`, create a webcal source.

**S13. SFTP host-key trust-on-first-use + no key management.** `connect_sshfs:1402-1427` uses `StrictHostKeyChecking=accept-new` (blindly trusts an unknown host, MITM on first connect) and `BatchMode=yes`, with no identity-file picker, no encrypted-key passphrase path, no known_hosts review. Sketch: `StrictHostKeyChecking=ask` with a fingerprint prompt exposed to QML; add `-i` key selection.

**S14. Proxy bypass list is hardcoded.** `Proxy.qml:24` writes `no_proxy=localhost,127.0.0.1,::1`; `Common/Settings.qml:470-471` exposes only `proxySocks`/`proxyPac` — no user-editable bypass list. Sketch: add `proxyNoProxy` setting and interpolate it into the environment.d line.

**S15. Radio stations from a third-party directory played without scheme validation or metadata.** `Radio.qml:95` fetches over `curl -sf`; `:119` plays `s.url` straight from the directory with no allow-list (plain `http://` ICECAST allowed), and no ICY/Shoutcast now-playing metadata or redirect display. Sketch: require https-or-explicit-opt-in, surface stream title.

## Needs server/daemon or privileged helper

**D1. OAuth2 token acquisition/refresh.** `agenda.py:551-598` stores a one-shot password (`store_password_sync`) with `auth.set_method("plain/password")` at `:572`; no refresh-token flow, so expired credentials leave EDS waiting on a prompt nobody shows. Needs a token-refresh daemon/keyring integration.

**D2. CalDAV sync conflict resolution.** `agenda.py:445-519` calls `create/modify/remove_object_sync` with no ETag/If-Match or conflict surfacing — concurrent edits from another device silently overwrite. EDS holds the sync state; needs EDS/daemon-level conflict reporting plus a UI.

**D3. Files network protocol depth.** `files.py:1328` accepts `nfs://` though gvfs has no NFS backend (generic failure); `:1332-1342` only feeds user/domain/password to `gio mount`, with no SMB dialect (SMB2/3 vs SMB1) or Kerberos/GSSAPI choice, and no WebDAV auth-method selection. Needs privileged `mount`/gvfs options.

**D4. rclone backend config and encryption.** `files.py:1207,1266` only *detects* existing rclone FUSE mounts; there is no backend config UI, no `rclone crypt`/`rclone config --password` path. Needs a config daemon/service.

**D5. Per-app proxy.** `Proxy.qml` sets only system-wide gsettings/env; `flatperm.py` has no proxy key. Needs Flatpak/system proxy configuration at the daemon layer (alongside the already-listed "proxy never reaches bridges").

**Skipped:** all eight passes' listed items (Cc/Bcc, attachments, IMAP timeout, account import, ODRS, OPML categories, CalDAV/CardDAV import, proxy→bridges). **Risk:** S3 (UID bug) can target the wrong message once a user searches then flags; S1/S2 are credential-exposure and connection-failure risks. Every finding is from source reading — no live IMAP/CalDAV/SMB/OAuth server was contacted.

## VERBATIM: Audio routing and PipeWire graph depth

# Ninth-pass research — audio routing & PipeWire graph depth (static only)

### Corrections first (the topic brief was stale — do NOT re-file these)

- **10-band EQ, bass boost, compressor, loudness (EBU R128), stereo width/mono, crossfeed, spatialiser, AutoEq, impulse response are all built** — `shani/Modules/Settings/SettingsSound.qml:105-263`, `shani/Services/SoundFx.qml:83-160`. GAPS.md:545 and the brief's "equalizer missing" are obsolete.
- **Device switching on plug-in/BT-connect is delegated to WirePlumber and OSD-reported** — `shani/Services/Audio.qml:137-161`.
- **Per-app volume mixer and per-app output routing exist in code**: mixer `shani/Modules/ControlCenter/SidebarSliders.qml:73-93`; routing helper `Audio.moveStream()` via `pw-metadata target.object` at `Audio.qml:95-103`.
- **RNNoise mic suppression** at `SoundFx.qml:232-291`. **Wake word / TTS voice** remain noted only (`SettingsChronoa.qml:37`, `GAPS.md:1803`; `Speak.qml:25` hardcodes spd-say/espeak). Skipped per instructions: BT codecs, mic AGC, loopback, per-sink delay, sound theme, record-what-system-plays.

### Shell-fixable gaps (ranked value × ease)

1. **Per-app output picker absent from the mixer.** `Audio.moveStream()` exists but app rows only expose volume/mute (`SidebarSliders.qml:75-92`). *Sketch: add a sink dropdown per app row calling `Audio.moveStream(modelData, sink)`.*
2. **Echo cancellation is detection-only.** `echo_cancel_active()` never enables anything (`bridge/shani_link/audio.py:66-81`; `bt_telephony.py:276-291`). *Sketch: mirror the RNNoise filter-chain pattern (`SoundFx.qml:238-291`) with an AEC fragment + Settings toggle; the report must stop listing it as missing.*
3. **No separate mic monitoring level.** Mic slider is capture gain only (`SidebarSliders.qml:31-48`). *Sketch: monitoring slider over a monitor source + loopback, default off.*
4. **Lock-screen media controls are shallow.** Only prev/play/next and art (`LockScreen.qml:416-445`); sidebar has player switching + seek (`SidebarNowPlaying.qml:80-92`). *Sketch: reuse the sidebar card, add seek bar, volume, `Media.cycle()`.*
5. **Media keys follow a sticky preferred player.** `Media.current = preferred || playing || first` (`Services/Media.qml:13-15`); a newly-starting player is ignored while a preference is stored. *Sketch: prefer `isPlaying` unless pinned this session.*
6. **No limiter / true-peak ceiling.** 150 % over-amplification distorts; only a compressor exists (`SettingsSound.qml:56,248-263`). *Sketch: append a LADSPA limiter to the filter chain (`SoundFx.qml:83-160`).*
7. **No notification/media ducking.** No `duck` reference outside URLs/search engines (grep). *Sketch: lower `Audio.players` gains briefly on notification/call via Settings toggle.*
8. **Recording has no latency compensation or live monitoring.** Desktop+mic are muxed after capture (`Services/Recorder.qml:44,50-60`); voice recorder uses `pw-record` with no monitor (`VoiceRecorder.qml:65-66`). *Sketch: expose `adelay` offset + a monitor toggle.*
9. **Channel remap/swap not exposed.** Only L/R balance (`Audio.qml:110-135`); a mono remap sink is created in `Services/Access.qml:35-42`. *Sketch: add channel_map choices to that remap module.*
10. **Album-art fallback missing.** `trackArtUrl` used raw (`SidebarNowPlaying.qml:62`, `LockScreen.qml:418`); empty/embedded-only art shows a blank tile. *Sketch: media-app icon fallback + small cache.*
11. **Wake word is a label, not a control.** Only "wake word" text pointing into Chronoa (`SettingsChronoa.qml:37`); no in-shell always-listening state. *Sketch: either expose real enable/phrase controls or mark explicitly delegated.*

### PipeWire/daemon-level gaps

12. **A2DP↔HFP auto-switch on mic use.** `set_profile()` exists and is correct (`bt_telephony.py:338-360`), and card profiles appear in Settings (`SettingsSound.qml:78-103`), but switching is manual/skill-driven; no WirePlumber policy reacting to capture start. *Needs a wireplumber Lua policy script.*
13. **Beamforming for mic arrays.** No `module-beamforming`/spatial filter anywhere; only single-source RNNoise (`SoundFx.qml:250`). *Needs hardware-specific filter-chain config, not a shell toggle.*
14. **No virtual sink/source or device-combining UI.** Only the accessibility mono remap (`Access.qml:39`). *Needs `module-combine-sink`/null-sink management exposed via shell commands.*
15. **No PipeWire graph viewer or arbitrary patching UI.** `Audio.qml:87-94` reads `linkGroups` internally only. *Needs a graph panel driving `pw-link` / `pw-dump` (daemon tooling, large).*
16. **Per-app recording.** Recorder captures the whole-output monitor or default source only (`Recorder.qml:44,51`). *Needs per-stream `target.object` capture via PipeWire policy.*
17. **TTS voice selection** confirmed unbuilt (`Speak.qml:25`); needs speech-dispatcher/espeak voice enumeration, not just UI.

**Highest value × ease:** #1 (routing UI already has the helper), #2 (filter-chain pattern already in repo), #3, #4.

**Skipped/not checked:** no runtime/hardware verification — AEC availability, Beamforming hardware, and HFP negotiation were assessed only from static source and the existing reports. Risk: #1's `moveStream` relies on WirePlumber honouring `target.object`; confirm on real hardware before shipping.

## VERBATIM: Developer tooling experience

# Ninth-pass gap research — developer/tooling experience for people extending the shell

All findings below are new vs. the eight passes (the only prior statement was one line in `docs/GAPS.md:1286` / `docs/GAPS-RESEARCH.md:481`: "no IPC reference/stability contract"). Static only. Ranked by value × ease.

## Hot reload

**1. No QML reload — every edit needs a full shell restart.** `dev/session.sh:241` starts `qs -p /work/shani` once; `dev/render.sh:124-132` literally `pkill -f 'qs -c shani'` then re-sources `dev/session.sh`. The only "live reload" in the repo is settings data (`Common/Settings.qml:1-4` watches its JSON file) — not QML source. *Sketch:* add a dev-only `shani ipc call shani reloadUi` that restarts just `qs`, or a watcher OnQmlChanged calling it.

## Debugging

**2. No IPC call tracer.** The `IpcHandler` has **519 functions** (`shani/shell.qml:258`, count to end); none logs invocation, args or result. *Sketch:* wrap calls in `Log.scoped("IPC").debug(name, args)` behind `SHANI_LOG=IPC:debug`.

**3. The in-code logger is effectively unused.** `Common/Log.qml:1-57` defines `SHANI_LOG` filtering, but `Log.scoped` appears only twice in real code (`Services/Files.qml:27`, `Common/Proc.qml:24`); `console.log`/`warn` total 4 across all of `shani/`. A developer editing a Service has near-zero runtime visibility by default. *Sketch:* adopt `Log.scoped` at Service entry points and document the filters.

**4. No in-shell view of the shell's own diagnostics.** `Modules/Logs/LogsPanel.qml:1` reads `journalctl` — system logs, not `qs.log`. QML output goes to `out/logs/qs.log`, bridge stderr to `out/logs/bridge.log` (`dev/session.sh:193,241`), readable only by leaving the GUI. `chronoa-bridge.py:450` prints just `bridge up: …`, no request log. *Sketch:* add `shani logs --follow` or a dev overlay tailing both files.

**5. No programmatic discovery of IPC functions beyond one fixed blob.** `state()` (`shell.qml:998`) returns a hand-picked JSON of UI state; no `listIpc`/`help`/`describe`. `bin/shani call` requires knowing the exact name; `shani ipc list` (a Quickshell builtin) is not surfaced. *Sketch:* add `IpcHandler.listFunctions()` or `shani call --list` that exposes reflection.

## Scaffold / boilerplate

**6. No scaffold command for a new app / module / service / bridge.** The only generator is `tools/i18n.py extract → template.json` (`tools/i18n.py:64`). *Sketch:* `dev/new.sh <name>` emitting a `pragma Singleton` + bridge docstring + test stub.

**7. Adding one IPC call means three manual edits.** Define it in `shell.qml:258`, add it to `bin/shani` `GROUPS` and the `_register()` table (`bin/shani:769`), then a test. No codegen keeps them in sync. *Sketch:* `dev/gen-cli.py` producing `_register()` from `qs ipc list` or a single manifest.

**8. A shell "app" has no single registry.** It must be added to the hardcoded `APPS` dict (`bin/shani:425`), a `Ui` boolean, an IpcHandler function, a `state()` line, and the launcher modules. *Sketch:* `shani/apps/*.json` consumed by CLI, PKGBUILD `--write-desktop` (`bin/shani:598-640`), and shell.

## API docs / discoverability

**9. Common components and Services singletons have no contract docs.** ~60 files in each of `shani/Common/` and `shani/Services/`; the only developer description is the prose layout list (`README.md:291-318`). *Sketch:* one-line "properties/signals/contract" header per singleton, or `docs/API.md`.

**10. Bridge command contracts exist only as per-file docstrings.** e.g. `bridge/tasks.py:1-12`, `bridge/cleanup.py:1-9`; no aggregate authored-facing guide and no version marker in any of the ~70 bridges. *Sketch:* `tools/gen-bridge-docs.py` extracting the docstrings into `docs/BRIDGES.md`.

## Testing

**11. No QML unit-test harness.** `tests/` is pytest only: static regex checks (`tests/test_qml_patterns.py:1`), subprocess bridge tests, and full-shell IPC integration. No `qmltestrunner`, `TestCase` or `SignalSpy` anywhere (`grep` of tests/dev/Containerfile: none). A developer cannot unit-test a new QML component. *Sketch:* add `qmltestrunner` to `dev/Containerfile` + a `qml` suite in `dev/check.sh`.

**12. No per-component test template.** Even the fluent pattern — a bridge test like `tests/test_devwatch.py` — must be hand-copied; there is no `tests/templates/` or `check.sh unit <name>` shortcut. *Sketch:* ship a copy-me `tests/test_<name>.py` and QML `TestCase` stub.

**13. Dev loop is container-only.** `dev/check.sh:56-84` builds/needs Docker plus a sibling `$SHANI_DESKTOP_NIRI` and `shani-testbed`; no documented host-native `qs -c shani` development path (the symlink at `README.md:323` assumes a live session). *Sketch:* document a minimal host env for QML-only iteration.

## Packaging for testing

**14. Dev install only symlinks QML.** `README.md:323` links `shani/`; Python bridges are installed to `/usr/lib/shani-shell` by the PKGBUILD (`../shani-pkgbuilds/shani-shell/PKGBUILD:164`). `dev/session.sh` compensates with `SHANI_*_TOOL=/work/bridge/...` env vars for tests only — nothing installs a modified bridge for real use. *Sketch:* `dev/install.sh` symlinking `bridge/` and `bin/` into packaged paths.

**15. PKGBUILD is pinned to a git commit — no local-checkout build.** `PKGBUILD:126` `source=(git+…#commit=4772748…)`; no documented override to build the working tree. *Sketch:* `dev/pkg.sh` with `source=("$PWD")` and `pkgver` from git.

**16. No checklist of files a feature must touch.** PKGBUILD installs QML by `cp -r shani` (`:136`), bridges by glob (`:164`), desktop entries via `--write-desktop` (`:197`), plus ad-hoc PAM/systemd/wallpaper lines. Adding a systemd-activated bridge or new asset has no documented packaging step. *Sketch:* `docs/PACKAGING.md` mapping source paths → installed paths.

## Versioning

**17. No API version for IPC or bridges.** `pkgver=0.1.0` and `/etc/shani-version` are product versions; no `SHANI_IPC_VERSION`, bridge `--version`, or deprecation field anywhere. External tools cannot pin a contract. *Sketch:* a version constant in `shell.qml`, expose it in `state()`, print it from `bin/shani --version` and each bridge `--version`.

Skipped: CONTRIBUTING/CI/theme-pack/Settings-hardcoding/man-page/command-palette (already listed), and the generic "no IPC reference" line — this pass is strictly about the *extension* workflow. Risk: all findings are static; no QML runtime or container was used, so the absence of a reload mechanism is inferred from scripts, not observed.

## VERBATIM: Config migration and versioning

# Ninth-pass gaps: configuration migration & versioning across updates

Read GAPS.md and GAPS-RESEARCH.md; skipped the four listed items. Static only. Nothing edited. Ranked by value × ease.

## High value, cheap

**1. No schema version exists in any state file — only a release-notification marker.** `Settings.qml:1-6` documents the JSON format with no version; `feeds.py:45-77` (`CONF`, `subs()`, `conf()`), `mail.py:44-56`, `music-library.py:124-130` all use bare dict shapes. The only version-ish state is `WhatsNew.qml:20-34` (`/etc/shani-version` + `whats-new-last.txt`) — a "tell me once" flag, not schema. Sketch: add `_schema: N` to every writer, a `migrate(obj, version)` dispatcher on every load, and quarantine unknown-future versions.

**2. Existing users never receive changed defaults.** "Created on first change" (`Settings.qml:2`) is misleading: `writeAdapter()` (`:118`) writes *all* ~300 keys at once — asserted by `dev/shell-test.sh:266-267` (`"caffeine": false` appears after toggling it). `applyOutside` (`:101-105`) always prefers the file value over `defaults[k]`, so a release that changes an existing default is invisible to anyone who ever toggled one setting. Sketch: persist a `touched[]` set; re-apply new defaults only to untouched keys, gated on a settings schema version bump.

**3. Renamed/removed keys are neither migrated nor cleaned.** The only historical transform is a one-off `dockAutoHide → dockVisibility` (`:98-100`). `applyOutside` loops `Object.keys(defaults)` only (`:101`); `snapshot()` enumerates every adapter key (`:39-48`) and `SettingsPage.qml:101-107` `resetAll()` also loops defaults only — stale keys survive even a full reset, and a renamed key silently loses its value. Sketch: a `retiredKeys` map of `{rename, transform, drop}` applied in `applyOutside` and `resetAll`.

**4. Corrupted `settings.json` is the only file with a safety net.** `Settings.qml:141-152` copies to `.unreadable-<ts>` and notifies. Every other loader silently resets: `ScreenTime.qml:85`, `Launcher.qml:122`, `Shelf.qml:33`, `PlayQueue.qml:70`, `Clipboard.qml:26`, `Notifs.qml:169,214`, `Reopen.qml:78`, `Weather.qml:28`, `VoiceRecorder.qml:53`, `TextDocs.qml:95`, `Updates.qml:34`, `Tr.qml:70,79` (~14 QML sites) and `feeds.py:60-65`, `mail.py:50-56`, `music-library.py:129-130,198-199`, `PhotosWindow.qml:82`. Sketch: one shared quarantine-and-notify helper used by all state loaders.

**5. Most of those same files are written non-atomically.** Only `Settings.qml:137`, `Updates.qml:33`, `Notifs.qml:208` set `atomicWrites: true`. `ScreenTime.qml:81-53`, `Shelf.qml:29`, `PlayQueue.qml:66/72`, `Weather.qml:22/34`, `Reopen.qml:72/93`, `Notifs.qml:165`, `Launcher.qml:119`, `PhotosWindow.qml:56` (plain `open("w")`) don't. Crash mid-write → corrupt JSON → gap 4 → permanent loss of screen-time/app-usage history. Sketch: set `atomicWrites: true` on every state `FileView`; tmp+`os.replace` in `metaWriteCode`.

**6. Corrupt `feeds.json` / `mail.json` destroy subscriptions and account config.** `feeds.py:60-65` catches `Exception` and returns the default; `_save` (`:68-75`) then overwrites it. `mail.py:50-56` same. This is irrecoverable user data, unlike the regenerable library cache. Sketch: quarantine bytes + toast before returning default.

**7. No downgrade migration across blue-green rollback.** `/home` is a separate subvolume (`gen-efi.sh:658` mounts `subvol=@blue|green`; `shani-reset.sh:21-24` confirms `/home` separate), so `~/.config/shani-shell/settings.json` outlives both slots. A setting written by the new version is read verbatim by the old one; no compat check or downgrade transform exists anywhere. Sketch: stamp settings with the writing version; on startup, if writer > current, quarantine or run a reverse transform.

## Medium

**8. Pre-deploy home snapshots aren't version-labelled and only two are kept.** `shani-backup/home.py:131` names them `predeploy-<timestamp>`, `:229-244` keeps 2; `shani-deploy.sh:73-75`, `shani-snapshot-home.sh:5-13`. To roll settings back to a specific release you must guess which timestamp. Sketch: `predeploy-<version>-<ts>` and expose version in `home list --json`.

**9. Factory reset preserves all per-user shell config/state.** `shani-reset.sh:21-27` explicitly leaves `/home` and `/root`; `shani-first-boot.sh:43-49` deliberately keeps theme/wallpaper. No scoped "reset just the shell" exists outside the in-app `Reset all settings` (which has gap 3). Sketch: `shani-reset --shell-config` clearing `~/.config/shani-shell` + `~/.local/state/shani*`, with dry-run listing.

**10. Dev session doesn't isolate bridge state.** `dev/session.sh:44` redirects only `SHANI_SHELL_SETTINGS` and `XDG_CONFIG_HOME`; bridges derive paths from `HOME` (`feeds.py:45-46`, `mail.py:44`) and `Quickshell.statePath()` uses unset `XDG_STATE_HOME`. Test runs write real `/root/.config` and `/root/.local/state` files. Sketch: redirect the XDG state/data/cache roots to a scratch dir too.

**11. No settings import from GNOME/KDE/COSMIC editions.** Export is one-way (`Appearance.qml:117`, `Access.qml:31` write gsettings); Setup has no importer; profiles are separate images (`shani-install-media/image_profiles/{gnome,plasma,cosmic}`). Sketch: a Setup page reading `dconf dump`/kconfig and mapping dark mode, accent, fonts, time format.

**12. Wrong-but-valid JSON passes silently.** `feeds.py:70-73` calls `.get("feeds", [])` on any parsed type; `ScreenTime.qml:85` accepts any type as `days` then `Object.values` (`:17`); `Tasks.qml:75-86` assigns parse results unchecked. Sketch: type-check (`isinstance`/`Array.isArray`) and quarantine mismatches, not just parse errors.

**13. No migration tests exist.** No test in `tests/` or `dev/` mentions version/migration/stale keys; `dev/shell-test.sh:33` writes a minimal file and `dev/session.sh:222-225` rewrites it wholesale. Sketch: `tests/test_settings_migration.py` with renamed/removed/unknown keys and a deliberately corrupt file.

**14. State lives in four different roots with four different corruption stories.** Webapps in `settings.json` (`WebApps.qml:16`), photos in `~/.local/share/shani-photos/meta.json` (`PhotosWindow.qml:55`), notes in `~/Documents/Notes` + hidden `.trash/.history` (`QuickNotes.qml:38-51`), passkey registry inside a keyring secret (`passwords.py:325-344`). Sketch: one `shani-state` helper implementing version + quarantine for all.

**15. Two different version files.** `shani-deploy` reads `/etc/shani-version` (`shani-deploy.sh:1547-1550`, `WhatsNew.qml:24`) while `shani-upgrade-adviser.sh:44-49` reads `/etc/shani/version`. Any future version-gated migration would read the wrong one on some systems. Sketch: one canonical path referenced by both.

Skipped: runtime verification of rollback with real settings, and whether Quickshell's `JsonAdapter` keeps undeclared JSON keys as dynamic properties (the stale-key outcome differs slightly between "persisted forever" and "dropped on next save"; neither migrates). Risk: if you add a schema version, the pre-deploy snapshots only cover two updates, so a third update makes an older config unrecoverable.

## VERBATIM: External-app interoperability

# Ninth pass — external-app interoperability (static only)

Read `GAPS.md` + `GAPS-RESEARCH.md` (8 passes). Skipped the parent's list (menus/AT-SPI, appmenu registrar, drag-out — built, RemoteDesktop portal, focus stealing, always-on-top) and items already filed elsewhere (mailto/geo handlers, "share into our apps", plain-text copy path — now `text/uri-list` at `Services/Files.qml:922`, grouped notifs, urgency-2 DND bypass, FileChooser-only portal, window thumbnails). What follows is new or materially deeper.

## Shell-fixable — ranked by value × ease

1. **Per-app rules cannot target a *named* workspace.** `SettingsWindows.qml:186` hardcodes `["","1"…"5"]`; the writer already emits any name (`WindowRules.qml:49`). A rule for a workspace called "chat" is impossible from Settings. *Sketch:* replace the Choice row with a free-text field populated from `niri msg workspaces`.

2. **Window-rule UI covers ~6 of niri's ~25 rule properties.** `WindowRules.qml:40-55` emits only mode/workspace/output/size; border, `focus-ring`, `opacity`, `background-effect`, `geometry-corner-radius`, `draw-border-with-background`, `block-out-from` and dynamic `is-focused` rules are only global (`SettingsWindows.qml:29,101-117`) or in hand-written KDL (`etc/niri/config.kdl:104-178`). An opaque legacy X11 app cannot get "no border" or a screencast blackout from the shell. *Sketch:* add per-app border/blur/opacity picks plus an "advanced KDL" passthrough reusing `NiriConfig.write`.

3. **No "screenshot this window" for an external app.** `Screenshots.qml:112` wires only `screenshot-screen`; `WindowMenu.qml` has no capture action. *Sketch:* add a menu item calling niri's window-capture action, then the existing annotate/copy pipeline.

4. **Inbound drag accepts file URIs only.** `Files/FileDropArea.qml:14` `keys: ["text/uri-list"]`; `Common/DropZone.qml:86-89` checks only `hasUrls`. X11/xwayland-satellite apps (`shani-desktop-niri/PKGBUILD:15`) commonly offer `UTF8_STRING` / `text/plain;charset=utf-8` paths; GTK/GIMP/Firefox offer `image/png`. No target in Photos, QuickLook, Annotate, Text Editor or Mail compose accepts either. *Sketch:* accept `text/plain` paths and `image/*`, spool to a temp file, reuse `Files.importPath`.

5. **DropZone trusts any URL scheme.** `Common/DropZone.qml:87-88` forwards all URLs; an `http://` drag from a browser becomes a bogus local path. *Sketch:* filter `file://`, decode URI.

6. **Mail is a dead row in Default Apps.** `SettingsDefaultApps.qml:23` queries `x-scheme-handler/mailto`, but no installed entry declares it (`bin/shani:528` mail mimes `[]`; skel `mimeapps.list` has no mailto/message/rfc822) — the row can only say "No app installed". *Sketch:* register both types on `dev.shani.Mail` and seed a default.

7. **No scheme handlers on any of our desktop entries.** `bin/shani:598-606` writes only `MimeType`; skel registers `magnet`/`dht`/`tel`/`ftp` to third parties but nothing for `mailto`, `geo`, `message/rfc822`, `web+*`. A link clicked in Vivaldi or a Flatpak never reaches our Mail/Maps. *Sketch:* add `x-scheme-handler/*` tokens to `APPS` mimes + default lines.

8. **Minimise/restore forgets the original workspace.** `Niri.qml:117-122` restores to the *currently focused* workspace; `:139-150` show-desktop parks all windows in "minimised". An external app comes back on the wrong workspace after Show Desktop. *Sketch:* remember `workspace_id` per window at minimise and move it back on restore.

9. **Flatpak portal notifications bypass our rule engine as first-class objects.** No code references `org.freedesktop.portal.Notification`; `niri-portals.conf` delegates `Notification=gtk`, and `NotifsRules.qml:49-78` matches `appName/summary/body` only. Relayed notifications may carry a different app id, so silent-app/rule matching can silently miss. *Sketch:* normalise relayed notifications by desktop id before `evaluate()`; verify with a real Flatpak chat app.

10. **Snoozed notifications lose identity and actions.** `Notifs.qml:143-163` re-posts with `notify-send`, dropping the `desktopEntry` hint that drives badges (`Niri.countFor`, `:30,39`) and all actions; a snoozed chat can't be replied to. *Sketch:* persist the hint/action payload and re-post over D-Bus.

11. **X11 PRIMARY selection is unsynced.** `etc/niri/config.kdl:100` runs `wl-clip-persist --clipboard regular` only — no `--primary`, no X clipboard manager. Middle-click text from an XWayland app never reaches Wayland apps or cliphist. *Sketch:* start a primary watcher and feed `clipboard-watch.sh`.

12. **XWayland input-method env is incomplete.** `config.kdl:84-94` sets `XMODIFIERS`/`QT_IM_MODULE` but no `GTK_IM_MODULE`; `fcitx5-gtk` ships (`shani-input-fcitx5/PKGBUILD:13`). GTK apps under xwayland-satellite may not load the module. *Sketch:* add `GTK_IM_MODULE "fcitx"` and verify on a real GTK app.

13. **Share sheet shells out instead of using portal Mail/Share.** `Share.qml:32` runs `xdg-email --attach`, `:35` `gio open`; `bridge/portal.py:35-42` implements only FileChooser. A Flatpak's Share intent or "Open with our Photos" cannot route through our sheet. *Sketch:* own portal Share/Email, or at least make `gio open` resolve to our apps via #7.

## niri / portal-level (no shell fix)

14. **Sharing one window to a Flatpak exposes the whole monitor.** portal-wlr 0.8.4 captures outputs only; `Niri.qml:240-264` manages casts globally with no per-window source. *Sketch:* portal-side window capture (upstream portal-wlr).

15. **No compositor session manager**, so external X11 apps cannot veto/save on logout (already filed at compositor level; restated for this topic's completeness).

16. **XWayland per-app scaling** is compositor-owned; `SettingsDisplays.qml` scales per output only. *Sketch:* niri-level Xwayland scale hint.

**Skipped / not checked:** no runtime or real Flatpak/XWayland app was available — items 9, 12, 14 are static inferences needing a booted image. I did not re-audit the eight already-filed menu/portal/notification gaps beyond confirming their evidence still stands. Risk: niri's exact rule/action names and `screenshot-window` availability were not verified against the installed binary, so the sketches may need a `niri msg action` name check before coding.

---

# Eighth pass — VERBATIM agent reports

## VERBATIM: Non-technical user documentation & UX

# Eighth-pass audit — non-technical user documentation & UX

Read: `overview.md`, `faq.md`, `troubleshooting.md`, `intro/*`, `install/*`, `system/{printing,backup}.md`, `updates/shani-reset.md`, `whats-new.md`, `setup/shell.qml` + `strings.js`, bridge/QML error strings, `index.html`. Static only. Items already fixed in prior passes (COSMIC, Translator name, dependency table, HTML stubs, whats-new refinements) skipped.

**Ranked by value × ease (H/M/L).** Evidence is quoted with file:line.

## A. Task orientation & onboarding (highest value)

1. **(H/H) No "how do I…?" entry point.** `overview.md:120-133` "How to Use This Wiki" is a table of *internals* — "Concepts… Architecture deep-dives", "Boot process, Btrfs layout, dracut". A person asking "how do I connect a printer / back up my photos / share files / set up email" has no landing page. *Fix:* add a "Common tasks" card list linking the existing `system/printing`, `system/backup`, `networking/samba`, `servers/mail` pages.
2. **(H/H) First steps are all terminal commands.** `intro/getting-started.md:104-158` "Recommended First Steps" = add Nix channel, `gen-efi enroll-tpm2`, `shani-deploy`, `flatpak install …`, `waydroid init`. *Fix:* lead with "open Software and search for an app"; label every terminal step "optional / advanced".
3. **(H/H) "How do I install an app?" never names the GUI first.** `faq.md:43-50` answers with `flatpak install flathub`, `nix-env`, `distrobox create`, `podman run`. *Fix:* first line "Open the Software app and search — that is the normal way"; keep CLI below.
4. **(H/H) Bug reports are developer-only.** `faq.md:332` "include the output of `uname -r`, `cat /etc/shani-version`, `cat /data/current-slot`, and relevant `journalctl` logs"; `troubleshooting.md:681-690` repeats the pattern. *Fix:* "tell us what you were doing and what you saw; attach a screenshot — or copy diagnostics from Cassini".
5. **(H/M) Encryption choice explained as internals.** `install/steps.md:18` "Enable LUKS2 full-disk encryption (argon2id key derivation)". No consequence, no "can't change later". *Fix:* "Encrypt my files (recommended for laptops) — if the laptop is stolen, nobody can read your files. Remember the password; it cannot be changed later without reinstalling." (The reinstall consequence exists only later at `faq.md:263`.)
6. **(H/M) Setup wizard omits encryption entirely.** `setup/shell.qml:36` pages are `welcome,keyboard,network,time,account,chronoa,done`; `setup/strings.js` has no encryption strings. The choice was made in the installer and never explained in plain language. *Fix:* one plain-language summary line on the account/"done" page: "Your files are/are not encrypted; change requires reinstall."
7. **(M/H) Chronoa and account *are* explained well** — the one bright spot: `strings.js:13` "It runs on your own computer, with no cloud and no cost. Turn it off if you prefer"; `:31` "This account… can install software and change system settings." Use this as the template for findings 4–6.

## B. Troubleshooting written as developer notes

8. **(H/H) Fixes are command dumps, not "if X do Y".** `troubleshooting.md:28-49` "System Won't Boot" opens with six commands (`grep -o 'subvol=@[a-z]*'`, `ls /data/boot_failure`, `journalctl -b -1 -u mark-boot-in-progress.service…`) before telling the user the system usually recovered itself (stated at `:30`). *Fix:* lead "If the screen stays black after an update, reboot once — it usually fixes itself."
9. **(H/M) Unexplained TTY.** `troubleshooting.md:81` "Switch to a TTY (Ctrl+Alt+F2 or F3) and log in". *Fix:* "Press Ctrl+Alt+F2 for a plain text login screen (Ctrl+Alt+F1 returns)."
10. **(M/H) "If X, do Y" is used in places — copy that pattern.** `troubleshooting.md:291` "If you see 'Locked notes need gpg…', `gpg` is missing… Install `gnupg`…" and `first-boot.md:78-87`'s symptom table are the right shape; most other sections are not.
11. **(M/M) Engineered correction note.** `troubleshooting.md:70-74` "There is no `shani-deploy --repair-boot`… gives `unrecognized option`" is useful but speaks flag names; no GUI alternative offered.
12. **(M/M) Developer-speak fingerprint answer.** `faq.md:241` "the PAM service comes from the login manager… `plasma-login-manager` (`plasmalogin`), whose PAM services never reference `pam_fprintd`". *Fix:* "On GNOME your fingerprint works at login; on KDE only at the lock screen; on COSMIC it is not available yet."

## C. Jargon without plain-language gloss

13. **(M/H) Security section opener.** `overview.md:22` "Six Linux Security Modules run simultaneously (`lsm=landlock,lockdown,yama,integrity,apparmor,bpf`)… Intel ME kernel modules not blacklisted by default". *Fix:* one sentence "These are independent locks on the system; a fault in one does not open the others."
14. **(M/H) Navigation table aimed at newcomers.** `overview.md:129` "**Security** | Polkit tiers, LUKS, TPM, AppArmor, Secure Boot, audit, hardening". *Fix:* "Password rules, disk encryption, fingerprint and secure boot."
15. **(M/H) D-Bus / AT-SPI unexplained.** `overview.md:76` and `faq.md:147` "menus… read over D-Bus and AT-SPI". *Fix:* "the top bar reads the app's own menu" (keep the protocol names in parentheses for technicians).
16. **(M/M) Jargon wall before the simple steps.** `system/printing.md:13-15` opens with CUPS, `ipp-usb`, eSCL/AirScan, WSD, SANE, `cups-pk-helper`, then only at `:20-26` says "Settings → Printers → Add Printer". *Fix:* move the GUI steps to the top and retitle the rest "Under the hood".
17. **(M/M) Backup jargon.** `system/backup.md:138` "restic is fast, cryptographically secure, and content-addressed. Every file is deduplicated…". A GUI alternative exists at `:13` (Deja Dup/KBackup) but is buried after two pages of CLI. *Fix:* promote `:13` to the opening.
18. **(L/M) Printing permission note.** `system/printing.md:87` "`cups-pk-helper` gates printer administration via Polkit". *Fix:* "Adding a printer asks for your password — that is normal."

## D. Step completeness, safety, product errors

19. **(H/H) Destructive restore with no warning.** `system/backup.md:95-98` "**Restoring the entire home directory**: `sudo btrfs subvolume delete /home`" — deletes today's files, said nowhere. *Fix:* "⚠️ This deletes all current files in your home; copy anything you still need first."
20. **(M/H) Factory reset leads with mechanism, not consequence.** `updates/shani-reset.md:9` opens "`shani-reset` wipes all persistent system state stored in `/data`"; the irreversible warning is at `:52` and again at `:128`. *Fix:* open "This deletes your accounts, Wi-Fi passwords, and — with `--home` — every personal file. Back up first. It cannot be undone."
21. **(M/M) Wrong-slot recovery lacks the plain outcome.** `troubleshooting.md:58-74`: steps plus an internal note, but never "your files are safe; only the OS version changes" until `:16` in the Golden Rule. *Fix:* repeat the reassurance in-section.
22. **(M/M) Raw backend errors reach users.** `Passwords/…Window.qml:69` "The keyring could not be reached: %1" with raw JSON `error`; `SoftwareWindow.qml:203-207` passes `flatpak` "No such file / permission denied" text through; `bridge/cleanup.py:122,146` returns `r.stderr.strip()` / "flatpak is not installed"; `bridge/live-tv.py:306` returns `str(exc)`. *Fix:* small string maps to "That program isn't installed" / "Not allowed — run as Administrator".
23. **(L/M) No glossary anywhere.** `index.html` has good a11y (skip link `:140`, search `:190-200`, font/theme buttons `:207-217`, `aria-label`s throughout) and no screenshots in docs (so no alt-text debt), but no term-definition page. *Fix:* one `docs/glossary.md` page linked from the home "Quick Links".

**Skipped / risk:** I did not open a browser or run the site (static only), so rendering of the suggested card list is unverified; and I did not re-audit the six prior-pass topics. Highest-risk item is #19 — the restore command is genuinely data-destroying and currently unlabelled.

## VERBATIM: Session lifecycle

# Eighth-pass gap report — shell startup, shutdown & session lifecycle

Static only. Skipped the seven passes' existing items (session-restore layout, eager startup processes, niri crash recovery, suspend-unlocked/security, lock-screen/lock gaps). All findings below are from current source, unverified at runtime.

## Shell-fixable — ranked by value × ease

1. **Shell-internal long jobs don't inhibit idle suspend.** `Idle.qml:97-101` only honours ext-idle-notify/`ScreenSaver` inhibitors; `Files.qml:534,676-680` exists solely to *schedule* suspend after a copy queue drains, and `Recorder.qml:94-102`/`convert.py` run ffmpeg with no inhibition. So idle `Power.suspend()` (`Idle.qml:121-125`) can cut a copy, conversion or download mid-write. Sketch: when `_jobs.length>0 || VoiceRecorder.recording || Convert.busy`, arm the existing `logind.Inhibit("sleep","delay")` path or `org.freedesktop.ScreenSaver.Inhibit`.
2. **Debounced state writes are lost on immediate logout/poweroff.** `PlayQueue.qml:48-72` resume points flush on a 1500 ms timer; `VoiceRecorder.qml:49-55` counter on 800 ms; `TextDocs` session on change. `Power.logout/poweroff/reboot` (`Power.qml:223-225`) fire `systemctl`/`niri quit` with no flush. Sketch: a `Session.flush()` IPC that forces each store's timer before the destructive action.
3. **No "save your work" / app-close prompt on logout, reboot or poweroff.** `SidebarHeader.qml:216-227` is a single double-click "Sure?"; `Ui.closeAll()` (`shell.qml:216-233,269`) closes shell panels, not app windows; `TextDocs.qml:29` exposes `unsaved` that nothing consults. GNOME/KDE/macOS enumerate dirty apps. Sketch: gate `Power.*` on a dialog listing `TextDocs.unsaved` + recorder/converter state, with "Save & quit / Discard / Cancel".
4. **Recorders and conversions are never finalised at session end.** `Recorder.stop()` sends SIGINT deliberately (`Recorder.qml:69-76`); `VoiceRecorder.stop()` too (`VoiceRecorder.qml:90-105`); on logout neither is called, so Opus/MP4 containers stay open. Sketch: call both `stop()`s and await `onExited` before `systemctl`.
5. **No resume handling at all.** `logind.py:66-72` re-inhibits on `PrepareForSleep(false)`; `Lock.qml:28-42` has no `resume` op. Media isn't paused/restored, `BtAgent.reconnect()` (`BtAgent.qml:50-60`) and display/wallpaper state aren't re-applied, no network re-check. Sketch: emit `{"op":"resume"}`, pause `PlayQueue`, re-run reconnect + per-output layout.
6. **No shutdown/logout hook for user scripts.** `Hooks.qml:17-22,69,99-107` has startup + lock/unlock hooks but no session-end event. Sketch: add `shutdown` key, fire it from the deferred `Power.*` path (ties to #2/#3).
7. **UPS "save your work" is a dead-end toast.** `Ups.qml:52-54` tells the person the machine "will shut down soon" but the shell offers no countdown, "shut down now", or deferral, and no coordination with #3. Sketch: a UPS banner with the NUT-estimated time and a "Save & power off" action.
8. **Power confirmation hides its scope.** `SidebarHeader.qml:216-227`; lock screen uses an armed 4 s button (`LockScreen.qml:280-294`). Neither shows how many apps/unsaved docs will be lost. Sketch: put the count from #3 in the confirm step.
9. **Suspend can hang if no output is covered by the lock.** `Lock.qml:15,26` releases the sleep delay only once `secure` is set by `WlSessionLock` covering every output; with no outputs/headless resume the flag never flips. Sketch: cap the delay with a timeout or release on `PrepareForSleep` regardless of `secure` when there are zero outputs.
10. **Other logind sessions are invisible to the shell.** `greeter/shell.qml:104-120` only probes `/run/user/<uid>` to decide whether to ask for a password (keyring); there is no session list, no "log out other user", no multi-user awareness. (Distinct from the already-listed "switch user" gap.)

## systemd / compositor-level

11. **No startup readiness for niri, audio, network, keyring or Chronoa.** `shani-shell.service:5-9` has only `After/Requisite=graphical-session.target`; `Wants=shani-shell.service` in `niri.service.d/10-shani-shell.conf:6` adds no `After=niri.service`. By contrast the dev session waits for every daemon (`dev/session.sh:115-241`: pipewire 1.5 s, niri socket loop, keyring `busctl` loop, Chronoa D-Bus 30 s loop). Slow/absent dependencies only produce reconnect timers (`Bridge.qml:37-42`, `Niri.qml:466-472`, `Idle` probes at startup) and a partially blank first frame. Sketch: add `After=niri.service pipewire-pulse.service org.freedesktop.secrets.service shani-chronoa-daemon.service` + a "Starting desktop…" cover until `Niri.available && Bridge.connected`.
12. **`shani-chronoa-bridge.service` has no dbus ordering.** `chronoa-bridge.service:1-12` declares only `After=graphical-session.target`, no `After=dbus.socket`; `PartOf=shani-shell.service` is correct, but a bus-not-ready start prints "unavailable" and the bridge never retries `logind.start()` (unlike Bridge.qml's socket retry).
13. **No user-session stop protocol.** Logout is `niri.action("quit","--skip-confirmation")` (`Power.qml:225`); niri disconnects Wayland clients rather than issuing a save request. No `org.gnome.SessionManager`/XSMP equivalent exists, so external apps (LibreOffice etc.) cannot veto or save on logout. Compositor-level.
14. **`Restart=on-failure` only; no success-exit semantics.** `shani-shell.service:21-22`, `chronoa-bridge.service:11-12`. A clean shell exit (crash-recovery restart) leaves `Restart=no` behaviour undefined for pending bridge state; no watchdog.
15. **Sleep inhibition covers only sleep, not shutdown.** `logind.py:98` requests `Inhibit("sleep", …, "delay")`; there is no `shutdown` inhibitor, so a poweroff from #3's path has no equivalent grace period for a slow flush.

## Comparison

GNOME Session tracks inhibitor clients and shows `EndSessionDialog` with dirty apps; KDE `ksmserver` runs per-app save-then-quit with a fallback timer; macOS `loginwindow` calls `applicationShouldTerminate:`; Windows sends `WM_QUERYENDSESSION`/`WM_ENDSESSION` so apps can veto. ShaniOS has a two-click "Sure?" and `systemctl` — none of the four session-level contracts.

**Skipped / not checked:** no runtime, real logind session, suspend/resume or second-user boot was available — all verdicts are source-only; I did not re-audit the seven passes' items above. **Risk:** the startup-ordering and lock-secure findings are timing-sensitive and could be masked by systemd's actual `Before=graphical-session.target` edges on pipewire/keyring in the shipped image — needs one real boot to confirm.

## VERBATIM: UX consistency and tone

# Eighth-pass UX consistency audit — findings

Read-only, static only. Skipped all seven prior passes' items. All 52 apps + `Common/`, `Services/`, `greeter/`, `setup/`, niri config. 22 concrete inconsistencies, ranked value × ease.

## Terminology (cheapest wins)

**1. "Log out" vs "Sign out" for the *same* `Power.logout()` call.** `ControlCenter/SidebarHeader.qml:206`, `Ring/Ring.qml:84`, `Launcher/LauncherActions.qml:97` all say "Log out"; `TvHome/TvHome.qml:73` says "Sign out"; `shell.qml:107` says "sign out" in prose. Companion split: "Sign in automatically" (`Settings/SettingsUsers.qml:109`) vs "the adapter powers on when you log in" (`Settings/SettingsNetwork.qml:455`). **Canonical: "Log in / Log out" everywhere** (matches the power-menu vocabulary and the `logout` action name). Greeter `shell.qml:219` "Login failed" folds it into one word.

**2. "Devices" vs "Drives" for identical storage hardware.** `Files/FilesPanel.qml:521` labels the storage list "Devices" (model `Files.devices`); `ControlCenter/SidebarDrives.qml:24` labels the same kind of list "Drives" (model `Drives.drives`); `Disks/DisksWindow.qml:129,131,215,261,471` calls a disk "the device" / "block devices", while `FilesPanel.qml:630,2716,2717` says "USB drives". **Canonical: "Drives" for storage; "Devices" only for peripherals** (`Services/Plugged.qml:123` "Devices" for MIDI/serial/keys is correct).

**3. "Delete" used for a recoverable trash action.** `ControlCenter/SidebarNotes.qml:198` tip "Delete this note" calls `QuickNotes.remove()`, which *moves to `.trash`* (`Services/QuickNotes.qml:292-294`); `Camera/CameraPanel.qml:187` "Delete capture" calls `Camera.trash()`; `Feeds/FeedsWindow.qml:112` "Remove"; but `Notes/NotesPanel.qml:450` and `FilesPanel.qml:3111` say "Trash"/"Move to trash". **Canonical: "Move to Trash" for recoverable; reserve "Delete" for permanent** (`FilesPanel.qml:3112` "Delete for good…" is correct).

**4. Notebook/folder within one Notes surface.** `Notes/NotesPanel.qml:91` "New notebook" vs `Services/QuickNotes.qml:59,65` "No sync folder chosen"/"Sync failed — check the folder". Low priority — "notebook" is deliberate Gnote parity — but the sync path is a folder, so name it "sync location" instead.

## Error messages (highest value)

**5. Developer-grade bridge errors are rendered verbatim.** 32 QML sites do `root.error = r.error || …` (`Services/Files.qml:241,648,698,736,863,875,892,965,1094,1117,1129,1247,1317,1353,1378,1429,1550`, `Services/Archive.qml:346`, `Services/PdfViewer.qml:48,123,342`, `Services/Backup.qml:75,99`, …). The strings they receive are lowercase CLI internals: `bridge/link.py:309` `"usage: link.py <command> [args]"`, `bridge/files.py:533` `"already exists"`, `:541` `"that is not a name"`, `:1795` `"%s: %s" % (type(e).__name__, e)`, `bridge/passwords.py:290` `"no such key"`, `:244` `"a name and an email address"`, `bridge/drives.py:442` `"stopped"`, `:476` `"this drive is not locked with a password"`, `bridge/flatperm.py:137` `"not a permission: %s"`. **Canonical: bridges return `{code, message}` for logs; QML owns all user-visible text.**

**6. Command names and shell syntax leak into user-facing strings.** `Settings/SettingsSharing.qml:157` — "it needs cap_sys_admin `(sudo setcap cap_sys_admin+p $(command -v sunshine))`"; `Services/Files.qml:1307` — "Sync failed (rsync exited %1) — is rsync installed?"; `Services/Disks.qml:166` — "(is lsblk installed?)"; `Services/QuickNotes.qml:718` — "(is gpg installed?)"; `Services/WallpaperStyle.qml:55` — "matugen is not installed"; `Disks/DisksWindow.qml:471` — "lsblk could not find any block devices". **Canonical: "This feature needs X" + one action; put the command in a "Copy details" affordance.**

**7. Raw stderr appended to friendly text.** `Services/Archive.qml:187,235,297,354,382`, `Services/Tasks.qml:67`, `Services/Disks.qml:203`, `Services/Contacts.qml:238`, `Settings/SettingsStorage.qml:54`, `bridge/flatperm.py:141,157`, `bridge/ratbag.py:121` all use `stderr.strip().splitlines()[-1]` as the message — can surface paths, Python exceptions, locale-specific tool chatter. **Canonical: map known exit codes; log stderr; expose via details.**

**8. Actionable vs cryptic errors, no template.** Good: `Maps/MapsPanel.qml:242,245,654,661` "check the network and try again"; `Disks.qml:166`. Cryptic: `Services/Feeds.qml:131` "The feed reader could not answer"; `Services/Link.qml:87` "Link could not answer"; `Services/VoiceRecorder.qml:297` "Export failed"; `Services/Backup.qml:114` "Backup failed"; `Services/Firewall.qml:163` "The firewall refused that". **Canonical: `<what failed> — <cause or next step>.`**

**9. Case/tone split.** QML errors are sentence-cased ("Could not save", `Services/PdfViewer.qml:124`); bridge errors are lowercase ("already exists", "stopped", `bridge/files.py:533`, `bridge/drives.py:442`). **Canonical: sentence case at every display site.**

**10. Greeter/setup show raw PAM text.** `greeter/shell.qml:214` `root.error = message` verbatim, `:219` "Login failed"; `setup/shell.qml:330` `"error: signing in: " + message`, displayed bare at `:1288`. **Canonical: map auth status to "That password didn't work. Try again." + retry affordance.**

## Loading / progress

**11. Ten words for "busy".** "Looking…": `PhotosWindow.qml:290`, `Scanner/ScannerPanel.qml:78`, `DiskUsage/DiskUsagePanel.qml:71`, `MediaPlayer/RadioView.qml:46`, `MusicLibraryView.qml:59`, `NearbyWindow.qml:90`, `FilesPanel.qml:2716`, `SettingsPage.qml:538`, `SettingsPrinters.qml:221`. "Scanning…": `SidebarDrives.qml:66`, `ScannerPanel.qml:150,171`, `DiskUsagePanel.qml:211`. Plus "Working…" (`StudioWindow.qml:78`, `DisksWindow.qml:107`, `SoftwareWindow.qml:188,262`), "Loading…" (`FilesPanel.qml:1052`), "Searching…" (`CharactersPanel.qml:144`), "Computing…" (`KundaliPanel.qml:93`), "Comparing…", "Counting…", "Measuring…", "Cleaning…" (`FilesPanel.qml:1807,2042`, `SettingsStorage.qml:105,93`). ScannerPanel and DiskUsagePanel each use two different words for the same state. **Canonical: "Scanning…" for enumeration, "Working…" generic; specific verbs only when they name the operation.**

**12. Spinner used only on buttons.** `Common/Spinner.qml` is wired through `Common/Button.qml:78`; direct use only `VoiceRecorder/VoiceRecorderPanel.qml:356`. ~24 text-only busy labels in `Text` elements have no indicator or progress bar. **Canonical: shared busy status row (Spinner + label); use `Button.busy` where applicable.**

## Empty states / success / confirmation

**13. Four title grammars.** "No X yet": `PhotosWindow.qml:440`, `NotesPanel.qml:192`, `AuthenticatorWindow.qml:208`, `TerminalAppWindow.qml:188`, `StudioWindow.qml:155`. "No X": `SidebarClock.qml:64`, `TerminalAppWindow.qml:336,419,481`. "Nothing X": `TasksWindow.qml:240`, `FilesPanel.qml:1337`, `CalendarPanel.qml:1147`. "This folder is empty": `FilesPanel.qml:1046,1236`. **Canonical: "No <plural> yet" first-run, "No <plural>" when filtered.**

**14. Errors disguised as empty states.** `FilesPanel.qml:1046` "This folder could not be opened", `ArchivesWindow.qml:215` "bsdtar (libarchive) is not installed", `AuthenticatorWindow.qml:208` "The keyring is not running" all render through `Common/EmptyState.qml` with a faded 40px icon and `Theme.dim` subtitle. **Canonical: error card with danger icon/colour + retry.**

**15. Three success channels, no rule.** Settings-only toast: 6 sites, all `Settings/SettingsPage.qml:187,189,196,208,406,832` (Common/Toast.qml otherwise unused by apps). Inline notes: `Feeds.qml:143,180,199`, `WallpaperStyle.qml:83`, `FontsPanel.qml:99`, `Files.qml:878`. `notify-send`: `PdfSigner.qml:188`, `VoiceRecorder.qml:160`, `Camera.qml:204`, `Calculator.qml:640`, `Modem.qml:77`, `Ruler.qml:81`, `CallRecorder.qml:34`, `shell.qml:473`. PdfSigner does both at `:186` and `:188`. **Canonical: inline for results in an open app; notification only for background completion.**

**16. Success notifications bypass i18n.** `VoiceRecorder.qml:160` "Recording saved", `Camera.qml:204` "Video saved"/"Video stopped", `Calculator.qml:640` "Copied ", `Modem.qml:77` "Text sent", `Ruler.qml:81` "Copied " are bare literals while inline counterparts use `Tr.t`. **Canonical: wrap all in `Tr.t`.**

**17. "Click again" vs "Tap again" — even inside one file.** `DisksWindow.qml:152,171,215,261,291` "Click again to confirm" vs `:446` "Tap again to confirm". "Click": `FilesPanel.qml:373,614,3042`, `SoftwareWindow.qml:333,510,541`, `PasswordsWindow.qml:281,359,439`, `ContactsWindow.qml:444`. "Tap": `NotesPanel.qml:279`, `Viewer.qml:471`, `Processes.qml:407`, `SettingsPage.qml:289,380`, `ClocksWindow.qml:119`, `TasksWindow.qml:227`. **Canonical: "Tap again" (input-agnostic on a touch-capable desktop).**

**18. Three confirmation mechanisms.** Two-tap (dozens), modal (`FilesPanel.qml:2193-2194`), type-to-confirm (`SettingsUsers.qml:162`). **Canonical: two-tap reversible; type-to-confirm only for home-folder deletion.**

**19. Missing confirmation on irreversible deletes.** `Calendar/CalendarPanel.qml:1319` `Delete` → `win.deleteEditor()` (EDS, no undo); `Mail/MailWindow.qml:304` `Delete` → `Mail.remove()` (IMAP). Compare `FilesPanel.qml:3112` modal and `SettingsPrinters.qml:176` two-tap. **Canonical: two-tap both.**

## Shortcuts / icons

**20. Zoom modifier mismatch.** `FilesPanel.qml:100-104` and `TextEditorPanel.qml:442-444` use Ctrl++/Ctrl+-/Ctrl+0; `PdfReader.qml:238-240` uses bare `+`/`-`/`0`. **Canonical: Ctrl+ modifiers everywhere; bare keys as secondary.**

**21. Bare `W` means different things in adjacent apps.** `TextEditorPanel.qml:437` and `FilesPanel.qml:108` use Ctrl+W = close tab; `PdfReader.qml:236` uses bare W = fit width; `Switcher.qml:134` bare Q = close window; global `Mod+Q` = close-window (`dev/niri/session.kdl:223`). **Canonical: reserve bare letters for reader view modes, document the conflict.**

**22. Same "Move to trash" action, two icons.** Recoverable trash uses `edit-delete` in `FilesPanel.qml:3111` and `Viewer.qml:471`, but `user-trash` in `PhotosWindow.qml:418`, `TasksWindow.qml:225`, `StudioWindow.qml:139`, `ModelsWindow.qml:126`, `ContactsWindow.qml:442`, `FilesPanel.qml:508`. Related: `edit-clear-all` (mapped to "Clear all" in `Common/IconButton.qml:22`) is used for a single-item delete at `TerminalAppWindow.qml:180,475`. **Canonical: `user-trash` recoverable, `edit-delete` permanent, `edit-clear-all` bulk only.**

Skipped deliberately: ellipsis glyph (246 `…` vs 1 ASCII — already consistent), alarming words/"Please" (none found), OK/Apply (none in tree — Cancel/Done consistent), app-menu help buttons and empty-state missing actions (covered in pass seven).

Risk: all static; I did not verify how raw bridge strings actually render at runtime, nor whether any two "Delete" actions differ in recoverability beyond the code path shown. No files changed.

---

# Seventh pass — VERBATIM agent reports

## VERBATIM: Regional formats depth

# Seventh-pass: regional/locale format depth (static only)

**Scope note:** `docs/GAPS.md` treats i18n as translated words only (`:52-60`, `:1269-1276`, `:1729`) — it has *no* date/number-format claims. Everything below is new. Skipped per instructions: translation counts, RTL, `%2` plural hack, fontScale, slider, IME, greeter.

**Core finding:** `Common/Tr.qml` follows `locale.conf` live for *words* (`:22-31`), but **no `QLocale.setDefault` and no locale argument to `Qt.formatDate`/`Qt.formatTime` exists anywhere in the tree** (verified by grep: only `Qt.locale()` in `SettingsDateLanguage.qml:35` and `Radio.qml:77`). The format preview in Settings (`SettingsDateLanguage.qml:244-247`, `date "+%A, %x"`, `printf "%'.2f"`) promises grouped, locale-ordered output that no app actually renders.

1. **Dates ignore QLocale.** Every `Qt.formatDate(d,"d MMM")` uses the process-default locale (C/English at startup), never `Tr.lang`. `Services/Files.qml:1608-09`, `Services/Feeds.qml:103`, `Services/Mail.qml:39`, `Services/Agenda.qml:189`, `Services/Backup.qml:59`, `Services/QuickLook.qml:101`. Sketch: pass `Qt.locale(Tr.chosen||undefined)` as `Qt.formatDate`'s third arg.
2. **12/24h toggle ignored in 9+ surfaces.** `use24h` is honoured in Bar/Link/Clocks but not `Services/Feeds.qml:102`, `Services/Mail.qml:38`, `Services/Files.qml:1606`, `Services/Agenda.qml:189-190,240,265`, `Services/Backup.qml:59`, `Services/QuickLook.qml:101`, `Services/WorldClock.qml:80`, `CalendarPanel.qml:67,74,184,208,265` (always `HH:mm`). Sketch: gate each on `Settings.data.use24h`.
3. **Hardcoded English weekday/month arrays.** `Services/Weather.qml:166` `["Sun"…]`; `Common/DatePicker.qml:21`, `Modules/ControlCenter/Calendar.qml:42`, `Modules/Calendar/CalendarPanel.qml:128` `["Su","Mo"…]`. Sketch: `Qt.locale().dayName(i,QLocale.ShortFormat)` / `Qt.formatDate(d,"ddd")`.
4. **Fixed day-month order in all short dates.** Even with a real QLocale, `"d MMM"` forces day-first; en-US expects month-first. Same files as #1. Sketch: `Qt.formatDate(d, Qt.locale().dateFormat(QLocale.ShortFormat))`.
5. **File sizes mislabel binary bytes.** `Services/Files.qml:1591-95`, `Services/ObexReceive.qml:19`, `Services/FileActions.qml:101` divide by 1024 but print `KB/MB/GB`. Sketch: `KiB/MiB/GiB` (or decimal /1000).
6. **No number grouping / digit script / Indian grouping.** Numbers use JS `toFixed`/`toString` with `.` and ASCII digits: `Files.qml:1593-95`, `Services/Displays.qml:83`, Calculator display. No `toLocaleString`; no Devanagari numerals; no १,००० / 1,00,000. Sketch: `Number(x).toLocaleString(Qt.locale())`.
7. **AM/PM not localised or missing.** `"h:mm AP"` yields English AM/PM from QLocale; `Modules/ScreenSaver/Cover.qml:85`, `QuickPanel.qml:108`, `TvHome.qml:137` use `"h:mm"` with **no** AP → ambiguous 12-hour time. Sketch: include AP and use `Qt.locale().amText/pmText`.
8. **First day of week is monday|sunday only, not locale-derived.** `Common/Settings.qml:185`; applied in `DatePicker.qml:18`, both Calendars. Locales starting Saturday unreachable. Sketch: default from `Qt.locale().firstDayOfWeek`.
9. **ISO week numbering hardcoded.** `CalendarPanel.qml:31,117` (`isoWeek()`), `SettingsDateLanguage.qml:357-58` says "ISO weeks". Locale week-1 rules (US: week containing Jan 1) absent. Sketch: use QLocale/QCalendar week rules.
10. **Weather's imperial toggle is temperature-only.** `WeatherWindow.qml:186,188,259` always `km/h` and `km`; `Services/Weather.qml:183` requests only `temperature_unit`. Sketch: send `wind_speed_unit=mph` and pick `mph`/`mi` from `weatherUnits`.
11. **Maps distance always metric.** `MapsWindow.qml:116` `km()`/`m` hardcoded, no toggle. `SettingsDateLanguage.qml:237` writes `LC_MEASUREMENT`, but no app reads it. Sketch: reuse `Calc.js` unit table with a metric/imperial setting.
12. **No real currency conversion.** `Launcher/Calc.js:89-92` detects `100 USD in INR` but hands it to the Chronoa LLM (`Launcher.qml:365-366`); Calculator's converter tab has only physical units (`Calculator.qml:73`, `Calc.js:61-71`). No rates, symbols, or locale placement. Sketch: small rates bridge + `Qt.locale().currencySymbol`.
13. **Collation is codepoint/lowercase, not locale-aware.** `bridge/files.py:335-366` (`natural_key`, `name.lower()`), `bridge/contacts.py:130-135` (`sort_key`) sort Indic/accented names wrong; QML uses `localeCompare` with no locale (`Viewer.qml:361`, `Launcher.qml:288`, `AppPicker.qml:103`, `MusicLibrary.qml:39`). Sketch: `localeCompare(b, Qt.locale().name)` / Python `locale.strxfrm`.
14. **Locale setup: formats written but never consumed.** `SettingsDateLanguage.qml:235-240` writes LC_TIME/NUMERIC/MONETARY/MEASUREMENT/PAPER; `:324` claims "every language is installed"; but only hi.json/mr.json ship and QML formatters ignore all LC_*; change needs re-login (`:327`). Sketch: wire `Qt.locale()` from the chosen locale, or state the preview is illustrative.
15. **First-boot wizard sets LANG only.** `bridge/first-account.py:133` `localectl set-locale LANG=…`; no format/measurement choices at setup. Sketch: add a format-locale page that writes LC_* too.
16. **Per-event timezone is display-only.** `CalendarPanel.qml:67,74` falls back to local time for unsupported zones; GAPS.md:708-709. Sketch: use ICU/i18n timezone conversion for event rendering.
17. **No alternate calendars.** Calendar is Gregorian-only (`CalendarPanel.qml:87-92` JS `Date` arithmetic); Kundali hardcodes Lahiri ayanamsa (GAPS.md:1021). No Vikram Samvat/Hijri for Marathi/Hindi dates. Sketch: surface QCalendar/ICU calendar types behind a setting.
18. **Percent/sign spacing hardcoded.** e.g. `Services/Plugged.qml:92` `Tr.t("Battery %1 %", b)` — fixed space, no locale percent sign/placement. Sketch: `Qt.locale().percent()`-aware formatting. (Low value.)

Highest value × ease: #1–#5, #7, #10. Needs design: #12, #17. Risk: no QML runtime or locale data available to verify Qt produces Marathi/Hindi month names.

## VERBATIM: File-format compatibility matrix

# Seventh-pass gap research: file-format compatibility matrix (static, read-only)

Audited `bin/shani:425-586` (the authoritative MIME claim table), `shani-pkgbuilds/shani-desktop-niri/etc/skel/.config/mimeapps.list` (defaults), each bridge/QML decoder path, and `shani-shell/PKGBUILD`. No prior pass compared format *claims* to format *code*. Skipped per brief: EPUB reflow, archive-add limits, HEIC defaulting, OCR/scanner, subtitle formats.

**Ranked by value × ease. "FP" = Flatpak fallback exists.**

1. **Text Editor ships zero syntax grammars.** `TextMate.qml:16-20` scans `~/.local/share/shani-textmate` and `/usr/share/shani-shell/textmate`; `find -name '*.tmLanguage'|wc -l` = **0**, and `PKGBUILD:package()` installs none. Every file silently falls back to the regex highlighter (`TextEditorPanel.qml:224`). Sketch: vendor ~5 small `.tmLanguage` files (C/Py/QML/JS/JSON). FP yes.
2. **UTF-16 text is classified "Not a text file".** `TextDocs.qml:143` uses `grep -qI ""`; any NUL-bearing file (UTF-16/32) tests binary and is refused before FileView (`:179-195`) can decode a BOM. Latin-1 has no selector either. Sketch: BOM sniff in the probe, decode via a bridge with explicit codec. FP yes.
3. **Viewer's navigation list is narrower than its own MIME claims.** `Viewer.qml:37-39` `isImage()` accepts only 13 extensions; `bin/shani:438` claims JXL, PSD, TGA, PCX, EXR, HDR, DDS, QOI, PPM/PGM/PBM/PAM, XPM, XBM, ICO — all decodable via `kimageformats` per `PKGBUILD:35-40` — but they vanish from next/prev (`:360`). Sketch: derive `isImage()` from the claimed MIME set. FP yes.
4. **Photos grid excludes formats its own importer accepts.** `PhotosWindow.qml:113` scans only jpg/jpeg/png/webp/gif/avif/bmp; the import picker at `:285` offers heic/heif. Imported HEIC files never appear. TIFF/raw also absent. Sketch: extend the `find` filter. FP yes.
5. **QuickLook's format table lags every app.** `QuickLook.qml:28-36`: no heic/jxl/psd/raw in image, no epub/djvu/cbz in pdf, no deb/apk/rpm in archive, no aiff/wma in audio. Sketch: reuse the APPS MIME table. FP partial.
6. **OPML round-trip destroys feed categories.** `feeds.py:475-485` writes flat outlines with only text/title/xmlUrl; `:502-509` reads only xmlUrl. Tags are first-class in feeds.json (`:273,348-364`) and drive UI filters (FeedsWindow.qml:50-77). Sketch: emit/read `category=`. FP no.
7. **RPM is offered in the Archive picker but cannot be read.** `Archive.qml:54` includes rpm in types used by ArchivesWindow.qml:20; bin/shani:478-488 and mimeapps.list omit application/x-rpm; libarchive/bsdtar has no RPM reader. Sketch: drop rpm, or `rpm2cpio | bsdtar -x`. FP yes.
8. **Office documents have no shell path at all.** No DOCX/ODT/PPTX/XLSX MIME in bin/shani; only an icon (DesktopIcons.qml:65), a tidy category (tidy.py:32), defaults to OnlyOffice Flatpak (mimeapps.list:295-389). `pymupdf.office.to_pdf()` exists but needs a separate licensed package. Sketch: read-only PDF-render bridge or accept the Flatpak explicitly. FP yes.
9. **Mail cannot open local .eml, mbox, Maildir or MSG.** `mail.py:6,17` is IMAP/SMTP/MailHog only; MailWindow.qml:20-26 uses FilePicker solely to save attachments. message/rfc822 unregistered. Sketch: `open <path>` via email.parser plus MIME registration. FP yes.
10. **Media Player claims ~130 MIME types with no capability probe.** bin/shani:446-471 + mimeapps.list:409-507 default MIDI, DTS-HD, Amiga modules, RealAudio, niche video to a thin MediaPlayer{} forwarding to QtMultimedia's FFmpeg backend. Only failure surface is generic onErrorOccurred (:246). Sketch: probe `ffmpeg -decoders/-formats` once and narrow defaults. FP yes.
11. **Converter input sets much narrower than the player's.** convert.py:40-81 omits .mts/.m2ts/.vob/.3g2/.f4v/.rmvb and all documents, so PDFs/e-books cannot be converted. Sketch: extend VIDEO_IN/AUDIO_IN. FP partial.
12. **Converter output codecs hardcoded, quality 3 presets.** convert.py:82-92,144-196 emits only libx264/libvpx-vp9 and 3 CRF/bitrate tuples, no HEVC/AV1/10-bit/HDR; UI offers only Small/Balanced/Best. Sketch: expose codec + numeric CRF. FP yes.
13. **DjVu/PS/EPS defaults depend on optional tools.** PdfViewer.qml:283-298 requires ddjvu and gs; PKGBUILD lists djvulibre/ghostscript as optdepends, yet bin/shani:441-445 claims the MIME types unconditionally. Sketch: make them hard deps or gate the claim. FP yes.
14. **Calendar registers vCalendar but imports only VEVENT.** bin/shani:551 claims application/x-vcalendar; agenda.py:601-619 walks VEVENT_COMPONENT only, so VTODO/VJOURNAL in .ics/.vcs are dropped. Sketch: route VTODO to Tasks. FP no.
15. **Multipage TIFF shows only page 1.** Viewer.qml:169 converts with `magick "$1[0]"`; display is AnimatedImage (`:92-100`) with no page navigation. Sketch: render `[N]` pages like the PDF strip. FP yes.
16. **E-book/comic conversion has no test.** pdfform.py:124-137 topdf() is the single failure point for EPUB/FB2/MOBI/XPS/CBZ; no test mentions them. Sketch: one fixture per format. FP yes.
17. **QuickLook treats any extensionless file under 2 MB as text.** QuickLook.qml:103-104 only checks size, then heads it; binaries render as garbage. Sketch: sniff first bytes. FP no.
18. **Archive creation supports 4 formats despite reading 20.** Archive.qml:261 offers only zip/tar.gz/tar.xz/7z; .tar.zst/.tar.bz2/.cab readable but not creatable. FP yes.

Cross-cutting: the real matrix is 3 hard deps (kimageformats, qt6-multimedia-ffmpeg, python-pymupdf+libarchive) wrapped in a 130-entry MIME list asserted, never measured. Cheapest systemic fix: one startup capability probe filtering MimeType claims against installed decoders.

## VERBATIM: Disability-specific accessibility

# Twelfth-pass [seventh-pass] gap research — accessibility by disability group

Read the full GAPS.md (all six passes) and skipped its WCAG/live-region/AT-SPI-name/contrast/focus-trap/RTL/caption-a11y items. This pass is static only — no QML runtime or hardware.

## Shell-fixable, ranked by value × ease

| # | Gap (group) | Evidence | One-line sketch |
|---|---|---|---|
| 1 | **High contrast stops at the shell** (low vision). The toggle only swaps `Theme` tokens; GTK/libadwaita apps are explicitly set to `adw-gtk3`, and `Access.qml` pushes only screen-reader + text-scaling to gsettings. | `SettingsPage.qml:1308`, `Theme.qml:100`, `Access.qml:28-34`, `Appearance.qml:125-132` | On toggle, also set `org.gnome.desktop.a11y.interface high-contrast` and a real HighContrast GTK theme (or ship an adw HC variant). |
| 2 | **Flash alerts die at the lock screen** (deaf). Incoming calls are urgency-2 and always alert, but `FlashAlert` returns immediately while locked — a deaf user gets no call/doorbell visual when the screen is locked. | `FlashAlert.qml:25`, `Notifs.qml:259-263`, `shani_link/.../sip_accounts.py:930`, `landline/__init__.py:435` | Let the overlay flash run over `WlSessionLock`, or render a persistent visual call card there. |
| 3 | **Braille stack ships but is inert** (blind). `shani-accessibility` depends on `brltty`/`espeakup` yet has no `.install` enabling either; `/var/lib/brltty` is bind-mounted but nothing starts; plug-in only flips Orca's switch. | `shani-pkgbuilds/shani-accessibility/PKGBUILD:8-12` (no `.install` in dir), `image_profiles/.../fstab:546`, `Plugged.qml:143-146` | Enable brltty/espeakup units; add a Braille subsection (Orca prefs, per-display choice, status-cell message on shell events). |
| 4 | **TTS has no voice/language/pitch choice** (blind/speech). Only three speed chips; the rate line hardcodes spd-say/espeak arguments. | `Speak.qml:20,24-25`, `SettingsPage.qml:1332-1345` | List `spd-say -v`/`espeak -v` voices and expose voice + pitch alongside rate. |
| 5 | **Voice typing ≠ voice control** (motor). Dictation only transcribes and types via `wtype`; no spoken-command grammar, so "click OK"/"open Settings" are impossible. | `Dictation.qml:26-65` | Classify the transcript as command vs dictation before typing; dispatch commands over the existing AT-SPI/`wtype` paths. |
| 6 | **No switch access** (motor). Desktop navigation is gamepad-only (d-pad/stick/buttons); OSK supports arrow+OK but nothing scans it from a single switch. | `GamepadNav.qml:1-15`, `Modules/Osk/Keyboard.qml:255` | Add a timed linear scan (Tab/arrows/Enter) into the focused surface, driven by any bound key/button, with adjustable scan speed. |
| 7 | **Orca is fire-and-forget** (blind). Launches `orca --replace` and probes `command -v`; no AT-SPI env/registry assertion, no Orca preferences entry, no shell "describe this panel" command. Bar/dock *do* have names — this is depth, not labelling. | `Access.qml:18-27`, `shell.qml:205-209` | Set `QT_ACCESSIBILITY=1`/`GTK_MODULES=gail:atk-bridge` in the session env; add "Orca preferences" + a describe-surface IPC. |
| 8 | **Captions have no call source or speaker labels** (deaf). Only "speakers"/"mic" via `pw-record`; no per-app/call node and no "who said what"; no Settings entry (one Control Centre tile + `Mod+Alt+C` only). | `Captions.qml:15-18,42-48`, `SidebarTiles.qml:330-343`, `niri/config.kdl:195` | Add a third source bound to the active call's PipeWire node plus speaker labels, and surface the switch on the Accessibility page. |
| 9 | **Non-visual notifications are title-only and inert** (blind). Read-aloud speaks app+summary, never the body; no spoken/braille reply or dismiss; hard 2000-char cap. | `Speak.qml:20,38-43` | Add "read body" and map notification actions to spoken/braille commands. |
| 10 | **Magnifier is pointer-only** (low vision). The lens follows `MouseArea` position; keyboard/Orca users have no focus-follow (separate from the already-logged auto-refresh/loupe gaps). | `Magnifier.qml:73-84` | Add a "follow keyboard focus" mode reading `Niri.focusedWindow` geometry. |
| 11 | **No simple/essential mode** (cognitive). The ten-foot `FormFactor` is a layout preset, not a cognitive simplification; no toggle trims advanced pages. | `SettingsPage.qml:1305-1377` (no such row), `Theme.qml:166-176` | One toggle hiding advanced tiles/pages, forcing large targets and icon+text labels. |
| 12 | **No reading assistance / text-only mode** (cognitive/low vision). Select-to-speech is the sole aid; no line focus, ruler, font override or reading overlay. | `Speak.qml:28,45-50`, `SettingsPage.qml:1305-1377` | Add a global reading overlay with line highlight and a font override bound to `Theme.fontScale`. |
| 13 | **Dictation language is borrowed from OSK/captions** (speech). Only auto/en/mr/hi and no independent picker or confidence feedback. | `Dictation.qml:19-25`, `SettingsPage.qml:1346-1359` | Separate dictation language choice reusing installed Whisper models; show a transcript-confirmed value before typing. |
| 14 | **Audio-description tracks are unidentified** (blind/low vision). Sound tracks render by title/language only; no AD tag or dual-track mix. | `MediaPlayerWindow.qml:553-559`, `trackName()` `:116-119` | Flag known AD track titles and offer "description alongside main audio" via a second player. |
| 15 | **Distraction-free is notifications-only** (cognitive). Focus modes hold notifications; the bar, dock and chips stay fully present. | `Focus.qml:1-5,20-25` | Extend focus mode to hide non-essential bar chips and dim/collapse the dock. |
| 16 | **No global "always show labels" setting** (cognitive/low vision). `Chip` carries a label and Accessible name, but dense states are glyph-only and the Accessibility page has no label toggle. | `Bar/Chip.qml:24-26`, `SettingsPage.qml:1305-1377` | Add an accessibility setting forcing visible labels under bar/dock/quick tiles. |

**Low-effort note:** gap 1 is roughly a gsettings line in `Appearance.qml`; gaps 4, 13, 15 and 16 are single rows/choices in the existing Accessibility page. Gaps 3, 5, 6 and 8 are the real work.

**Compositor / AT-SPI-level — flag, don't promise:**
- Colour filters, HDR, gamma — niri has no colour management; already logged at `GAPS.md:29,1139,1522`. A layer-shell tint overlay would also tint the control that switches it off, so it is not a real filter.
- Dwell / eye- or head-pointer selection — no pointer position is available to a layer-shell client ("find my pointer", `GAPS.md:38`). The `dwell` timers in `HotCorners.qml:52-56` and `Ring.qml:175-189` are accidental-activation guards, not selection methods.
- Sticky / Slow / Bounce Keys — keyboard input is niri's (`GAPS.md:38,823`); only xkb options are writable from the shell.
- Native Wayland Qt 6 / Chromium AT-SPI menus — niri lacks the appmenu protocol (`GAPS.md:113-116`), so voice/switch users cannot reach those menus even with a scanner.

Skipped: every item already in the WCAG accessibility section and the six prior passes (live regions, AT-SPI names, `Theme.faint` contrast, focus traps, RTL, caption styling, magnifier auto-refresh/loupe, one-handed OSK). **Risk:** all 16 are source-reading verdicts — in particular the braille-service claim depends on no `.install` existing in `shani-pkgbuilds/shani-accessibility`, and the call-flash claim assumes incoming-call notifications keep urgency 2 at runtime; neither was verified on a booted image or with Orca/brltty hardware.

---

# Earlier passes — VERBATIM agent reports preserved from the original audits

## Sixth pass — AI / Chronoa integration depth (VERBATIM)

Feasible in the shell (ranked value × ease):
1. **No conversation history / new / switch / delete.** The panel's transcript is one in-memory `ListModel`, wiped with the shell; the backend already has `reset-conversation`, `switch-conversation`, `delete-conversation` actions. (ChronoaSurface.qml:10-11; backend app/application.py:1849-1861) Add header "New / History" menu driving those existing D-Bus actions.
2. **Scripted `approve "deny"` can grant "Allow this once".** `optionFor()` forwards `options[0]` (the allow option) for any unrecognised decision — the exact failure its own comment warns about. (ChronoaPanel.qml:201-214, shell.qml:327-332, FINDINGS.md:175-179) Match `deny`/`always` semantically or reject unknown labels; never default to option 0.
3. **Cloud fallback is invisible in the Island.** Backend emits `notice "A cloud provider answered this turn"`; the shell puts it in the transcript only (panel must be open), never in the bar pill. (agent_service.py:213-214; ChronoaSurface.qml:47-48; Island.qml:80-93) Set a `lastCloud` flag on that notice and show a small cloud chip in the Island + panel header.
4. **Tool-choice ("selection") events are silently dropped.** The Agent emits a record of which tool was chosen and why; neither event handler has a case for it. (agent_service.py:26,206-207; Chronoa.qml:72-105; ChronoaSurface.qml:36-51) Render an expandable "chose `<tool>` because …" line for transparency.
5. **Suggested prompts are static.** Four hard-coded chips (Battery / Summarise screen / Tidy desktop / Dictate), no adaptation to focused app, clipboard or notification. (ChronoaPanel.qml:751-757) Derive chips from `Niri.focusedWindowId`, `Smart.suggestion`, `SmartReplies`.
6. **Window context is a title string.** "Ask Chronoa about this window" sends only title + `app_id`; file handoff sends paths as prose. (WindowMenu.qml:67-68; FileActions.qml:156; Island.qml:359-379 (bare ask)) Attach window id, workspace, app, selection and accessible summary to the text.
7. **No per-turn local/cloud or model switch in the panel.** The model chip is read-only; `defaultProvider` is informational; switching lives in Chronoa's own settings window. (ChronoaPanel.qml:359-375; AIProviders.qml:88-92) Make the chip a menu of installed models + providers, sent with the turn.
8. **Assistant replies are plain unformatted text** — no Markdown, links, code blocks or copy/regenerate/feedback controls. (ChronoaPanel.qml:547-577) Render with the backend's `markdown_lite.py` (or a local helper) and add copy/regenerate.
9. **Panel state labels ship untranslated** ("listening", "thinking", "speaking", "waiting for you", "offline", "ready") while the rest uses `Tr.t`. (ChronoaPanel.qml:79-91) Wrap in `Tr.t()` — strings exist in the template catalog.
10. **No voice / wake / barge-in controls in Settings > Chronoa.** Backend actions `toggle-wake-word`, `toggle-barge-in-vad`, `toggle-cloud-fallback` exist; the shell surfaces only enable/kill and a link to Chronoa's settings. (SettingsChronoa.qml:24-43; backend application.py:1724,1884, audio.py:1044-1052) Add three switches; the D-Bus plumbing already exists in `chronoa-bridge.action()`.
11. **No push-to-talk in the shell conversation.** Mic is tap-to-toggle; voice typing is tap-to-toggle; no hold key or interruption gesture. (ChronoaPanel.qml:843-877; Dictation.qml:26-31) Bind a hold key that calls `toggle-listening` / `stop-speaking` (both registered).
12. **Approvals have no audit trail or "always for this app" granularity** — decisions survive only as transcript text; no log of what was permitted. (ChronoaPanel.qml:191-195,715-724) Keep a shell-side decision ledger keyed by turn + app (`Settings.data`).
13. **No privacy / memory controls on the shell side.** All sense consent and "forget" live in Chronoa's own window; the shell only has an on/off switch. (SettingsChronoa.qml:24-43) Expose key sense toggles + a "Forget" button in the shell settings page.
14. **No streaming cancellation affordance** — `submit()` refuses input while busy; the stop button only stops speech, not the turn. (ChronoaPanel.qml:229-236,859-877) Add a Cancel button in the working state (needs #16).

Needs backend / model:
15. **Cannot cancel a running turn.** `Agent` has only Turn/Approve/Write/FindFiles; the bridge has no cancel op. (agent_contract.py (XML); chronoa-bridge.py:191-222) Add `Cancel(turn_id)` + an Event, wire shell button to it.
16. **No persistent screen sharing / live context.** Shell only passes one-off screenshot or Lens-region *paths in prose*; backend vision is per-turn. (Lens.qml:69-77; Screenshots.qml:140) A "share screen with Chronoa" toggle streaming frames or a vision sense subscription.
17. **No camera input to Chronoa.** Camera captures stills to disk, but there is no "ask Chronoa about the viewfinder." (Services/Camera.qml (still path); backend screengrab.py camera backend) Add a camera-attach button that hands a frame to the vision sense.
18. **No shell-app tool/prompt registration.** Backend MCP server exposes skills to Claude/Cursor, but Shani apps and Hooks cannot register tools or prompts with Chronoa. (backend mcp.py; shell Services/Hooks.qml (event scripts only)) Define a desktop-entry `X-Shani-Chronoa-Tool` manifest + an MCP bridge action.
19. **No per-app data-access provenance.** Consent is sense-based in the backend; events carry no "which app asked", so the shell cannot show an access timeline. (backend capabilities.py gating, agent_service.py event shape) Add caller/app id to events; shell renders a per-app access log.
20. **Model management is disconnected from the live model.** Models reads `ollama list` only; the panel guesses the label from a setting, cannot test connection or see fallback/offline state. (Models.qml:44-75; ChronoaPanel.qml:30-39) Expose a live model/provider registry D-Bus property and bind the chip to it.
21. **Voice output has no in-shell voice/style controls.** TTS/voices exist in the backend; the shell just watches PipeWire peaks on the Island. (Island.qml:111-118; backend tts.py, voices.py) Add voice/style pickers and an in-panel playback bar.
22. **No multi-session or cross-device continuity.** One turn at a time (`TurnFilter` holds 8 unclaimed turns); no handoff of a conversation to a phone/other app. (bridge/turn_filter.py:38-40; shell has no session id) Needs a session id in the Agent contract plus a resume/handoff action.

Skipped/did not re-list the already-audited Chronoa items (opt-in bug, dconf key mirroring, model-download notices, translator, semantic file search, launcher/popup "Ask Chronoa"), and did not runtime-test any D-Bus path, wake word, barge-in or a real vision model. **Risk:** items 15–22 depend on backend APIs that exist only in `shani-chronoa`; wiring the shell before those methods exist will silently no-op. Item 2 is a real security bug, not a feature gap — it should be fixed first.

## Sixth pass — Automations, hooks and routines (VERBATIM)

Shell rule engine (Services/Automations.qml):
1. **Captured special keys are silently discarded when the bind is written.** SettingsShortcuts.qml:71-80 can capture F1–F12, Space, Return, arrows, Home/End, but InputConfig.qml:146 keeps only `/^[A-Za-z0-9+_]+$/` — so those binds are recorded in Settings and never appear in `shani-input.kdl`. Fix the filter to emit niri key names, or stop offering uncapturable keys.
2. **No way to fire a rule manually.** `act()` (`Automations.qml:43-55`) is private; there is no IPC method, palette entry, or keybind action for "run this automation now". Expose `fire(index)` over `shani ipc` and add it to `SettingsShortcuts.qml:133-137`'s action presets and the palette.
3. **Trigger vocabulary is 5 items.** `holds()` `:32-42` supports only `wifi`, `power`, `output`, `displays`, `time`; the Chronoa engine already has 19 event types (`triggers/common.py:305-330`). Add app focus / window title, notification, clipboard change, USB/BT device (bridges `devwatch.py`, `plugwatch.py` already watch), battery *level*, and file change; reuse `bridge/clipboard-watch.sh`.
4. **Action vocabulary is 6 items.** `act()` `:43-55` = focus, dnd, volume, style, open, run. Missing: notify, play sound, lock/sleep, set arbitrary setting, open URL, media control. Route through existing shell IPC rather than adding per-action bridges.
5. **Failures are invisible.** `Automations.qml:51` `execDetached(["sh","-c",a])` discards exit status and stderr; `Hooks.qml:25-29` only catches a synchronous spawn failure. Capture output, log to a rule history, and toast a failed `run`.
6. **No loop or rate guard.** `:56-65` is edge-triggered only (`wasTrue`); an action that reverses its own trigger (a `run` that changes Wi-Fi/output, or DND toggling) can ping-pong forever. Add a per-rule cooldown and a max-fires-per-minute budget.
7. **Five unrelated "when X then Y" systems.** Shell rules (`Automations.qml`), shell hooks (`Hooks.qml`), keybinds (`SettingsShortcuts.qml`), Chronoa event/percept rules (`triggers/event_rules.py`), and Chronoa phrase routines (`routines.py`) have separate stores, formats, UIs and logs. Unify on one rule schema and one Settings page, with adapters for each actuator.
8. **`notificationRules` is a dead setting.** `Common/Settings.qml:260` declares `notificationRules: []`; `Hooks.qml` never reads it (0 matches). Either implement notification-triggered scripts or delete the key.
9. **No templates, import/export, or sharing.** `SettingsAutomations.qml:100-283` builds every rule from scratch; `setRules()` just overwrites the JSON array. Add starter templates ("office Wi-Fi → Work focus"), export/import of `Settings.data.automations`, and a shareable file/QR.
10. **No dry-run / test.** No way to ask "what would this rule do right now?" Add a Test button that calls `holds(r)` and prints the resolved action without `act()`.
11. **Rule edits have no undo.** `SettingsAutomations.qml:37,60,62` writes immediately; `Settings.qml:73-81` undo is per-key, taken at sign-in. Add a rule-level undo stack or reuse `undo(key)` scoped to `automations`.
12. **GUI caps at 3 screens and 6 volumes.** `SettingsAutomations.qml:184` offers only "1","2","3" although `holds()` `:38` parses any integer; `:236` offers only 0/20/…/100. Generate from `Displays.outputs.length`; use a slider like `TimePicker` at `:189`.
13. **Hooks share one global on/off.** `Hooks.qml:21` `_enabled()` gates all six; `SettingsAutomations.qml:69-75` has one switch. Add per-hook enable and a per-hook failure indicator.
14. **User scripts are unpermissioned.** `Hooks.qml:27` and `Automations.qml:51` run `sh -c` as the full desktop user with no confirmation, timeout, or audit. Add an opt-in confirmation for `run` rules and a bounded timeout.
15. **Time rules are "every day at HH:MM" only.** `Automations.qml:39,91-105` — no weekday mask, one-shot, sunrise/sunset, or timezone. `Appearance.qml:28-73` already computes sunrise/sunset, and Chronoa's `read_schedule` (`triggers/desktop_sources.py`) has weekdays + grace — reuse one.
16. **Startup quirk for time rules.** `prime()` `:71` deliberately excludes `r.when !== "time"`, so a rule matching the current minute at startup waits for the *next* minute boundary. Document or offer a "fire now if due" option.
17. **Wi-Fi match is exact string equality.** `:35` `wifiNow === is`; `output` uses a case-insensitive substring `:37`. Add regex/SSID-picker semantics and a "connects to any open network" predicate.
18. **No named/sound notification action.** `Notify` exists as a shell service but there is no `then: notify` (`:20-26`, `:43-55`) and no sound action; add both, with a message field in the author form.

Routines (Chronoa) and the trigger engine:
19. **Routines are phrase-only, not scene/schedule-driven.** `routines.py:54-73` matches a whole utterance; `skills/routines.py:13` only save/list/delete. Add optional schedule/app/location triggers and an explicit ordered step list so "good morning" is deterministic rather than model-planned.
20. **No import/export or sharing of routines.** `routines.save_all()` writes one local JSON; no bundle, QR, or cross-device sync. Add export/import of `routines.json` (same mechanism as other data-portability gaps).
21. **Percept rules have no unattended product caller.** `triggers/rules.py` `TriggerEngine` is reachable only via `shani-chronoa-sense trigger run`; `AmbientScheduler` drives only event rules. Wire percept rules into the daemon so "when battery < 20% then …" actually fires without a CLI.
22. **Event-rule authoring is skill-driven, not first-class GUI.** `skills/manage_triggers` is the only writer (`event_rules.json`); the shell's Settings never sees these 19 types. Surface the Chronoa event/rule list in the same Automations page (ties back to #7).

Comparison (Tasker / Shortcuts / Power Automate / Home Assistant): Consistently absent across all five systems: variables and expressions, condition branching (`if/else`), wait/delay steps, subroutines, loop/iteration, run history with replay, dry-run, and rule versioning. Home Assistant's device-state scenes and Shortcuts' shareable shortcut files are the closest references — #7, #9, #19 are the highest-leverage transfers.

**Not checked:** runtime behaviour, real hardware events (Wi-Fi/output changes), QML execution, or whether niri actually applies every generated bind. **Risk:** many shell actions call `sh -c` as the user (#14), so any new trigger source widens an already-unpermissioned execution path; #5/#6 should land before #3/#4.

## Sixth pass — Window management / niri depth (VERBATIM)

1. **Column swap is absent from the UI (only per-window swap exists).** `WindowMenu.qml:49-50` offers `swap-window-left/right`; niri's `swap-column-left/right` is never called anywhere in the tree. One menu entry each, mirroring the existing ones. *Sketch: add "Swap column left/right" using `focus-window` then `swap-column-*`.*
2. **Fullscreen / float / maximize menu labels never reflect current state.** `WindowMenu.qml:38,40,41,45,46` issue actions but render fixed labels; the `windows` objects carry `is_floating` only (`Niri.qml:346-355`), no fullscreen/maximized readback, so no checkmarks or "Restore" toggles. *Sketch: check `w.is_floating`, track fullscreen via `WindowLayoutsChanged` or an action-local map, relabel to "Exit fullscreen".*
3. **Force-kill works only on the *focused* window.** `Niri.qml:458-464` kills `focusedWindow.pid`; `LauncherActions.qml:62` exposes exactly that, and `shell.qml:931` `windowClose` sends only polite `close-window`. A frozen window named over IPC cannot be killed. *Sketch: `forceClose(match)` → `findWindows()` → `kill -9` its pid; add a "Kill this app" menu row gated on a confirm.*
4. **No create / delete workspace action.** Rename exists (`Bar.qml:364-378`, `Niri.qml:279-289`, IPC `shell.qml:899`) and reorder via `move-workspace-up/down` (`WindowMenu.qml:58-59`), but niri only creates workspaces implicitly; there is no "new workspace" or "close this workspace" in bar, ring, menu or IPC. *Sketch: bar context menu → `focus-workspace <next free>` then `set-workspace-name`; close = minimise its windows then `unset-workspace-name`.*
5. **Overview search throws away its context.** `OverviewSearch.qml:31-35` closes the overview and hands the typed string to the launcher; there is no search *within* the current workspaces/windows, no result list while the overview is open, and a typed query cannot select a window. *Sketch: filter `Niri.windows` locally and highlight through `focus-column-*` / `focus-window` before handing off on Enter.*
6. **Urgency is displayed but never acted on.** `Niri.qml:404-411` tracks `is_urgent` on windows and workspaces (`343-345`); the bar/map colour it (`Bar.qml:233,360-361`), but there is no "focus the urgent window", "switch to its workspace", or "flash its dock tile and stop when seen" policy. *Sketch: one IPC + a dock/bar badge action calling `Niri.focusWin()`.*
7. **Edge swipes are four hard-coded actions only.** `EdgeSwipe.qml:14-33` maps launcher / quick-settings / back / overview; no per-edge assignment, no "previous/next workspace" or "show desktop" swipe, no disabled toggle beyond the global `edgeSwipes`. *Sketch: expose an edge→action pick list in Settings and route through the existing `run()`; add `focus-workspace-up/down` cases.*
8. **No workspace-level drag reorder.** The build already has a drag proxy with MIME id in `Bar.qml:237-247` (used to drop a *window* onto a workspace), but workspace chips themselves have no drag target/source, so `move-workspace-up/down` (`WindowMenu.qml:58-59`) is the only reorder path. *Sketch: reuse the proxy; on drop call `move-workspace-up`/`down` N times, or index-to-index if niri gains `<index>`.*
9. **"Move workspace to monitor" only goes to the *next* monitor.** `WindowMenu.qml:60-61` and the window move `:55-56` both use `*-next`; named monitor targets exist only in IPC (`Niri.moveWindowTo` at `Niri.qml:193-201`, `shell.qml:933`) and in `swapMonitors` (`Niri.qml:210-234`). *Sketch: add a submenu of `Displays.outputs` calling `move-window-to-monitor`/`move-workspace-to-monitor <name>`.*
10. **General resize is percentage-only; no exact pixel or per-height UI.** `WindowMenu.qml:52-54` uses `set-column-width` percentages; `set-window-width`/`height` are used only by Media Player (`MediaPlayerWindow.qml:47-48`). No "set size" dialog, and height presets are keyboard-only (`session.kdl:285-287`). *Sketch: a size sheet with width × height px and proportion chips, calling `set-column-width`/`set-window-height` on the captured id.*
11. **Floating-workspace key is not monitor-namespaced.** `WorkspaceLayout.qml:15` keys by `ws.name || "output:idx"`; a *named* workspace on two monitors collides, and names are resolved on their own output (`Niri.qml:293-296`). *Sketch: always key by `output:idx` and keep name as a label; migrate old keys.*
12. **Session restore brings back app identities, not the layout.** `Reopen.qml:20-38,89-94` stores only desktop entry ids; window count, geometry, column widths, workspace and monitor placement are lost. Compare GNOME/Windows "restore windows". *Sketch: persist a compact `{app, count, workspace, output, tile_size}` snapshot from `Niri.windows` + `WindowLayoutsChanged`; reapply after reopen via `set-column-width` / `move-window-to-workspace`.*
13. **No focus-stealing / new-window focus policy.** Urgency events arrive (`Niri.qml:404-411`) but nothing implements "focus new windows", "focus only my workspace", or an allow-list; `SettingsWindows.qml:34` covers only pointer focus. *Sketch: a setting + `onWindowOpened` / `WindowUrgencyChanged` handler in the shell (niri itself has no configurable policy).*
14. **Swap monitors only swaps the two active workspaces.** `Niri.qml:210-234` operates on one active workspace per output and temporarily renames one; no UI to pick *which* workspaces to exchange, and columns are snapped to four preset widths (`:206-209`). *Sketch: a monitor-pair dialog listing `workspacesOn(output)`; reuse the width-preserving shell script.*
15. **No "focus previous workspace" bind or UI (previously noted, still open).** `InputConfig.qml:91` enables niri's `workspace-auto-back-and-forth` and `SettingsWindows.qml:37` exposes the double-tap setting, but `session.kdl:260-274` has no `focus-workspace-previous` / back-and-forth key and no bar action. *Sketch: bind `Mod+Tab` to an IPC `focusPrevWorkspace` using the existing focus history.*
16. **Overview has no window-level actions.** `OverviewStats.qml:37-42` can only close all; `OverviewSearch.qml:77-79` relies entirely on niri's arrow keys. No per-window close/minimise/pin while zoomed out, unlike KDE/GNOME overviews. *Sketch: a small action strip bound to the niri-focused window (niri's overview selection is not exposed in `Niri.qml`'s event handling — `OverviewOpenedOrClosed` at `:426-428` only gives open/closed).*
17. **Trackpad workspace/column gestures are entirely compositor-owned.** `session.kdl:19-25` states three-finger and four-finger gestures are niri's built-in with no config; `InputConfig.qml:157-166` writes only `dnd-edge-*` and turns hot corners off. No gesture enable/disable, direction remap, or sensitivity in any shell UI. **Compositor-only — out of scope for the shell** (track this as a niri feature request, not a gap to implement here).
18. **No monitor-hotplug workspace placement restore.** `Docking.qml:20-29` restores bar/dock/gaps on dock state change, but nothing remembers which workspace belonged to which output (`Niri.workspaces` are keyed by transient output+idx). *Sketch: persist an output→workspace-name map and re-run `move-workspace-to-monitor` on `Displays.outputs` change.*
19. **No crash-recovery UX for niri.** `Niri.qml:466-472` reconnects the event stream after 1.5 s but does not detect that niri died, show a banner, or verify config; `NiriConfig.qml:68-86` only restores files on `ConfigLoaded(failed)`. *Sketch: on repeated reconnect failure, notify "Compositor restarted" and offer `niri msg action` re-application of shell-owned state.*
20. **Always-on-top is genuinely impossible.** `Niri.qml:152-180` implements the floated-window "show on all workspaces" carry instead; there is no Wayland layer a client can request above other windows. **Out of scope (compositor). Do not file as a buildable gap; the existing docs already say so.**
21. **No Activities / multi-workspace-set abstraction.** niri exposes a flat per-output workspace list; KDE Activities, GNOME workspaces-as-separate-sets and macOS Spaces groups have no analogue. The shell's only grouping is `hiddenWorkspaceNames` (`Niri.qml:71-84`) and `floatingWorkspaces`. **Compositor-level model — out of scope** for a layer-shell client; a shell-side "workspace set" would have to rename and hide workspaces wholesale.
22. **No window thumbnails in switcher or overview.** `Switcher.qml:1-8` explicitly notes niri has no per-window capture protocol and uses icons. **Out of scope (compositor protocol).**

Already correct — not gaps: Focus-follows-mouse, warp-pointer-to-focused-window, workspace double-tap-back, named workspaces, per-app open-on-workspace/screen rules, hidden-workspace names and resize/snap presets are all implemented (`InputConfig.qml:90-95,124`, `SettingsWindows.qml:34,131-219,281-316`, `Bar.qml:364-378`). Kill-by-pid, rename and monitor swap exist but only in the forms listed above.

Skipped: runtime/hardware verification of any gesture, hotplug or overview behaviour; whether niri 26.04 actually implements all actions the shell issues (e.g. `move-column-to-side` is noted as ignored at `Services/WindowLayouts.qml:158`). Risk items 4, 12 and 18 touch persistent state and need a migration/backup path before shipping.

## Sixth pass — User documentation accuracy (VERBATIM)

HIGH:
1. Generated HTML for all three shell-related pages is stale. `shani-docs/doc/overview/index.html`, `doc/faq/index.html`, `doc/troubleshooting/index.html` — markdown was updated 2026-11-22 (commits `54cff3c`, `1a585ab`) but the stubs were last regenerated 2026-11-01 (`e540d3e`); working tree is clean. Concretely: `doc/overview/index.html` jumps from "Quick Links" straight to "Current Release" — the entire "The Shani Desktop / Built-in apps / Things worth knowing" section (`docs/overview.md:50-81`) is absent. The words "Disks", "Models", "Studio", "Feeds", "Firewall" occur 0 times in the stub. `doc/faq/index.html` omits the new "What apps does Shani Shell include?", "What do the newer apps do?", global-menu, window-arrangement and backup Q&As. `doc/troubleshooting/index.html` omits "Locked Notes Won't Unlock", "Global Menu Missing or Empty", "PDF Annotation or Conversion Fails", "Notes Sync Has No Cloud Folder", "Scrolling Screenshot Capture Fails". All three carry `dateModified`/`datePublished` of `2026-08-28…Z` and a visible "Updated 2026-08-28", contradicting `updated: 2026-11-22` in source. One stub even ships the old provider list "OpenAI, Anthropic, Mistral", while `docs/overview.md:60` and `shani/Services/AIProviders.qml:19-25` list OpenAI / Anthropic / Google Gemini / Groq / OpenRouter (+ Mistral via OpenRouter). Correction: run `node generate-manifest.js`, verify byte-identical on a second run, and commit the three regenerated stubs.
2. Edition count contradicts itself across shani-docs. `docs/overview.md:13` and `docs/faq.md:29` (both updated 2026-11-22) correctly say three desktop editions ship (GNOME, KDE Plasma, COSMIC). Still stale: `docs/intro/what-is-shanios.md:9` ("two desktop editions today… COSMIC announced and in development"), `docs/intro/comparison.md:29` ("COSMIC (announced)"), `docs/intro/comparison.md:112` ("upcoming release"), `docs/intro/getting-started.md:17` ("announced, in development… Watch shani.dev for its release"), `docs/intro/switching-from-windows.md:19` ("COSMIC *(announced)*"). `shani-install-media/image_profiles/cosmic/` and `iso_profiles/cosmic/profiledef.sh` confirm COSMIC builds today. Correction: change all five to "ships today".
MEDIUM:
3. Troubleshooting omits every new bridge/dependency failure mode. `shani-docs/docs/troubleshooting.md` names no external tool behind the new apps even though bridges emit explicit errors: `bridge/disks.py:61-62,193-194,256-257` → "smartctl is not installed (smartmontools)"; `shani/Services/TerminalApp.qml:85` shells out to `picocom` for serial; `bridge/location.py` → "no GPS fix from gpsd, and GeoClue is not installed"; `bridge/translate.py:19-25` needs llama-server on `127.0.0.1:8765` and exits 2 without it; global menu needs `at-spi2-core`; notes cloud sync needs `rclone`. Worse, `shani-shell/bin/shani-doctor.py:18-99` checks none of picocom, smartctl, GeoClue, llama-server or at-spi2-core. Correction: add a short "Shell app dependencies" table/section to troubleshooting.md and extend `shani-doctor.py`'s `FEATURES` list.
4. The ~70 mass-pass features have no user-facing home in shani-docs. There is no whats-new page in the docs site (nav/config contain none; `docs/updates/shell.md` is about Zsh/terminal, not the desktop shell). The granular refinements live only in `shani-shell/data/whats-new.md:19-31` and `FEATURES.md:190-222`. Correction: add a "What's new in the desktop" page (or a compact list in overview.md) linking to the shell's FEATURES.md.
LOW:
5. Wrong app name: `docs/faq.md:117` lists "Translator". The real app is "Translate" — `shani/Services/ShellApps.js` (`"Translate": "dev.shani.Translate"`) and `bin/shani:528` (key `"translate"`). Correction: "Translator" → "Translate".
Checks that passed: App count 50 consistent; 7 PDF annotation tools verified in `bridge/pdf-annotate.py`; clipboard transforms verified; provider list in `docs/overview.md:60` verified against `AIProviders.qml`; i18n catalog 3684 strings matches GAPS.md; stable version 2026.05.18 consistent (22 occurrences); `node tests/check-links.js`: 0 broken internal links (1179 across 206 pages); `check-ground-truth.py`: no bad flags/subcommands/units/SELinux; FORM-FACTORS/HARDWARE-VALIDATION cross-links resolve. FORM-FACTORS.md, RENDER-COVERAGE.md, HARDWARE-VALIDATION.md, UX-IMPROVEMENTS.md carry recent review dates and no concrete code contradiction found.
Skipped: live browser crawl and dynamic shell execution (static-only per brief). Risk: the site fetches current markdown at runtime for JS visitors, so finding #1 mainly affects no-JS/crawler views and structured data — but the stale stubs are committed and would be served as-is.

## Sixth pass — Security and privacy depth (VERBATIM)

1. **[CRITICAL, documented only in installer repo]** MOK private key shipped inside the base image (`shani-install-media/SECURITY.md:30-34`) and two real keys still retrievable from git history (`AUDIT-HISTORY.md:63-71`). Rotate + rewrite history — human decision. Also: Podman builds set `SigLevel = Never` and the AMI path soft-fails verification (`SECURITY.md:35-49`) — fail-closed all paths.
2. **[high]** The 45 s clipboard clear covers one of ~25 copy paths. Only `PasswordsWindow.qml:126` arms `wl-copy --clear`. Authenticator sets a 1.5 s *label* timer but never clears (`AuthenticatorWindow.qml:70,89,93`); all others write `Quickshell.clipboardText` directly — `Launcher.qml:316,321,330,361,364`, `TranslateWindow.qml:280`, `LensPanel.qml:84`, `Viewer.qml:287`, `Files.qml:403`, `Characters.qml:34`, `Ruler.qml:80`, `FontsPanel.qml:39`, `QrView.qml:88`, `CameraPanel.qml:151`, `SettingsAbout.qml:176`, `TerminalAppWindow.qml:473`. Sketch: single `Clipboard.copySecret()` that writes via `wl-copy` and restarts one global clear timer; route all secret paths through it.
3. **[high]** OTPs are admitted to cliphist. `looksSecret()` requires ≥8 chars and hex/base64/prefix patterns (`Clipboard.qml:37-53`); a 6-digit TOTP matches none, so `AuthenticatorWindow.qml:89` puts it in history permanently. Sketch: tag OTP copies as ephemeral; `clipboard-watch.sh` drops them.
4. **[high]** Phone share leaks whatever is on the clipboard, no confirm/secret filter. `SidebarDetails.qml:443` → `Phone.qml:27 kdeconnect-cli --share-text Quickshell.clipboardText`. Sketch: confirmation dialog + `looksSecret()` guard.
5. **[high]** Suspend can happen unlocked. `Lock.qml:33-38` releases the sleep delay without locking when `lockBeforeSuspend` is false (default true, but user-toggleable at `SettingsPage.qml:2016`); on resume there is no lock. Sketch: lock on suspend always; treat the pref as "lock before vs. after".
6. **[high]** "Notification previews" toggle also governs agenda and media titles. `LockScreen.qml:254,399,532` show next-event and track title under `lockPreviews`; `SettingsPrivacy.qml:107` only labels it "notification titles". Sketch: one `hideContentWhileLocked` gate covering all three.
7. **[high]** No audit trail. `Log.qml:40-47` writes only warnings/errors; `shani-admin.py:491-509` logs nothing; `SettingsPrivacy.qml:211` (permission revoke), `passwords.py:177,280,387` (deletes), unlocks in `Modules/Lock` emit no structured record. Sketch: `Log.audit("unlock|grant|admin|delete", actor, target)` → journald with UID; surface in Logs panel.
8. **[high]** Guest/enrollment privilege boundary is loose. `50-shani-admin.rules:19-22` grants `AUTH_SELF_KEEP` by regex on the *trailing token* (`/(autologin|power-keys|battery-limit)$/`); `guest`, `wakeup`, `lighting`, `power-limit` fall to admin (correct), but `caller()` returns `""` if `PKEXEC_UID` is absent (`shani-admin.py:138-143`), so self-demotion checks (`user_admin:199`, `user_remove:182`) silently pass. Sketch: refuse when `PKEXEC_UID` unset; match command name exactly, not suffix.
9. **[high]** Camera kill switch is a single-module unload. `Privacy.qml:17-20` runs `pkexec modprobe -r uvcvideo`; built-in cameras on other drivers stay live, and any wheel member can disable the module globally. Sketch: enumerate actual `/dev/video*` owners and the owning module; confirm scope.
10. **[high]** Clipboard encryption off by default and no migration (`Settings.qml:444`); enabling wraps only the existing DB once (`clipboard-crypto.py:149-155`). Sketch: default on, wrap on first run.
11. **[high]** `settings.json` is world-readable by umask and holds `clipPins`/server URLs (`Settings.qml:2,442,529`). Sketch: chmod 0600 after first write.
12. **[high]** Pinned clipboard text bypasses `looksSecret()` — `Clipboard.qml:139-140` pins any decoded text. Sketch: filter at pin time.
13. **[high]** Recent lists have clear-all only. `SettingsPrivacy.qml:163-165` `Housekeeping.clearRecent()`; no per-item removal, and URL/history entries in `filesRecentServers` have no UI at all. Sketch: per-entry delete + list in Privacy page.
14. **[high]** Lock-screen biometric can call `unlocked()` outside the password conversation with 3 retries and dropped `queued` (`Modules/Lock`, already noted at GAPS:1245-49) — still unfixed; add a single state machine.
15. **[high]** Note-crypto races and leaves plaintext (`note-crypto.py:47-53`; shared QML crypto Process per GAPS:1442) — serialize and keep plaintext in memory only.
16. **[D]** No DoH/DoT option. `SettingsNetwork.qml:547-550` offers only plaintext Cloudflare presets via `nmcli`. Sketch: systemd-resolved DoT toggle.
17. **[D]** No WebRTC leak protection / VPN kill switch surfaced anywhere; no WebRTC stack exists (GAPS:1080), so nothing blocks a browser's WebRTC while VPN tile is on.
18. **[S]** `.flatpakref` installs from arbitrary URL without showing the remote. `appstore.py:668-677` passes `--from` straight through. Sketch: parse and display origin + confirm.
19. **[S]** AppImage added executable with no signature/hash check. `appstore.py:541-607,555` chmod +x and writes a launcher from extracted metadata. Sketch: verify detached signature or warn prominently.
20. **[S]** No per-request consent for cloud LLM. `ModelsWindow.qml:202` and `AIProviders.qml:26-53` send prompts to the chosen provider using keys from Passwords; opt-in is only at setup.
21. **[D]** TPM seal is weak unless the user re-enrolls after first boot. Installer seals a literal PCR 0+7 policy without Secure Boot and defers pcrlock to `gen-efi.sh enroll-tpm2` (`os-installer-config/README.md:105-109`); nothing in the shell detects a stale seal or nags. Sketch: Cassini/About reports TPM policy age and re-enroll action.
22. **[S]** Shell exposes no TPM/Secure Boot state. `SettingsAbout.qml:263-275` only launches `shani-cassini --section=secureboot`; no state, re-enroll, or MOK status in the shell.
23. **[D/H]** MOK private key shipped inside base image and keys in git history (same as #1).
24. **[D]** Auditd is installed fleet-wide but the shell emits no audit records for its privileged actions; add rules for `shani-admin.py` and admin D-Bus calls.
25. **[D]** No retention/encryption control for voice recordings, Chronoa transcripts or call logs (no bridge file found for call logs); these persist unencrypted beside notes.

**Deliberate win, not a gap:** no diagnostic log upload and "Nothing is sent" in About — keep it opt-in if ever added.

## Sixth pass — Installer / upgrade / recovery UX (VERBATIM)

Shell-fixable (ranked): failed update toast no cause/retry; pending reboot cannot defer; no update history on Updates page; no support bundle at failure; no "last checked" time; health results text-only with no remediation actions; setup failure raw error with no retry; no Wi-Fi-only/metered warning before a multi-GB update; channel switch no explanation; Boot & Recovery read-only; two divergent health systems; Settings › About has no in-OS recovery entry.
Installer/daemon: no basic-graphics/safe-mode boot entry; image size/ETA not in deploy JSON; health recommendations not in JSON so UI cannot render actions; no "reinstall ShaniOS keeping files"; restoring an older snapshot is manual btrfs; failed-install help button dead (no browser on live ISO); encryption choice and recovery key not explained at install; metered enforcement needs daemon.
Deliberate win: no log-upload consent flow exists — report as a privacy win.
Two-desktop comparison: Shani already beats GNOME Software / KDE Discover / SteamOS / macOS / Windows Update on blue-green rollback and phase-level progress, but is weakest on exactly those human affordances: no pause/history/safe-mode/keep-files path and no failure-to-action bridge.

## Sixth pass — Specialized subsystems (VERBATIM)

Printing (driverless setup/default/test page already exist): missing ink/supply levels, scan-to destinations, real print dialog (copies/page-range/duplex/preview), in-shell job queue with cancel/hold, printer-state alerts.
Fonts system: missing hinting/antialiasing UI (hardcoded in `Appearance.qml:130`), font DPI control, font uninstall, cache refresh watcher.
Gamescope console (full session ships in separate package): missing MangoHUD overlay control, per-game TDP/frame-cap profiles, in-game screenshot/recording hotkeys, controller-remap and fan-curve tiles.
Casting: missing cast session state/sink list/stop, mirror-area choice (`--fullscreen` hardcoded), audio routing with cast.
Time/date (settings UI otherwise solid): missing NTP server configuration, sync status/source readout, dual-boot RTC mode, timezone-change feedback.
Freedesktop compliance: cross-volume trash restore, recent-files destruction by `Housekeeping.qml:27` (truncates all apps' recents daily), thumbnail metadata and cache bound, more thumbnail sizes.

All sixth-pass verdicts are static — no runtime, hardware, PAM/polkit, TPM/MOK, printer, gamescope or live deploy verification was possible.

---

# Fifth pass — VERBATIM agent reports

## VERBATIM: Reliability and data integrity

1. **Deterministic temp filenames defeat atomicity when two processes overlap.** Every "atomic" JSON save in the bridges uses a *deterministic* temp path, so a concurrent second invocation truncates the first's temp and both `rename`s race: `bridge/feeds.py:72` (`feeds.json.tmp`), `bridge/mail.py:67` (`conf.json.tmp`), `bridge/appstore.py:216` (`appstore-index.json.part`), `bridge/files.py:799` (`starred.tmp`), `bridge/music-library.py:164,221` (`library.json.tmp`), `bridge/translate.py:185`, `bridge/copyjob.py:91`, `bridge/u2f.py:65`. Concrete: the Feeds refresh timer (`Services/Feeds.qml:88`) and a user mark-read can call `save_cache()` at once → interleaved write + `os.replace` → corrupt cache JSON that `_load()` then silently resets. **Fix:** `tempfile.mkstemp(dir=path.parent)` for every temp, as `pdfform.py:168`/`note-crypto.py:47` already do.
2. **Bookmarks file written non-atomically.** `bridge/files.py:1684` — `bookmark()` does `open(f, "w")` directly (read at 1676, truncate at 1684), so a crash/ENOSPC mid-write leaves an empty or half bookmarks file; `starred()` 30 lines above already uses tmp+`os.replace`. AppImage `.desktop` entry same (`appstore.py:599`).
3. **Singleton races:** TerminalApp.qml uses one shared `cbStore`/`testProc` for Test Connection; two quick clicks strand one callback. QuickNotes.qml uses one crypto Process with four shared mutable fields (`mode`, `pendingPass`, `newName`, `payload`) — an autosave racing a lock can apply the wrong mode.
4. **Keyring.qml:26-33 hides write failures with `|| true`.** Same class that caused "AI keys never stored". A locked Secret Service or full disk reports success while the secret never lands.
5. **Three of four gpg calls have no timeout.** `bridge/lock.py:98-105` `_gpg()` passes `**kw` through; only decrypt at :226 supplies `timeout=3600`. Calls at :139,146,235 have none — a gpg-agent blocked on a locked keyring/pinentry hangs the Files bridge forever. convert.py conversions no timeout/SIGTERM cleanup; QML Process no watchdog (bsdtar, pdftoppm, wf-recorder, libcamera can leave UI stuck).
6. **nearby.py receive leaves `.part` files with no recovery.** Receive writes `target + ".part"`; a crash/SIGKILL mid-upload leaves an orphan in the Inbox, no sweep, no resume. clipboard-crypto.py can leave plaintext `*.db.wrap` symlink after SIGKILL; conversions/transfers accumulate `.part` across crashes.
7. **Voice Recorder takes lost on ungraceful SIGTERM/logout.** Only SIGINT finalizes the Opus file (`VoiceRecorder.qml:90-105`); a logout, crash or System Monitor SIGTERM gives no finalization and the whole take is lost.
8. **Disk-full errors hidden:** feeds.py/mail.py never check write result and UI reports success. Caches keyed only by path+mtime (appstore.py:206, music-library.py:145, files.py:960). Tasks.qml:75-86 assigns JSON.parse output with no type check — `{}` breaks every delegate. files.py:1672 re-records IPC paths without rejecting newlines or `..`.

## VERBATIM: Offline and network resilience

1. **[shell-fixable]** Proxy settings never reach running bridges — Proxy.qml writes gsettings + environment.d for next login while bridges inherit startup env; SOCKS mode sets no ALL_PROXY.
2. **[high]** mail.py IMAP calls no timeout (:376-382); Updates.qml:66-69 no timeout/re-entrancy guard — one hung shani-deploy wedges all checks; fwupdmgr likewise. Translate interactive requests inherit 300s batch timeout.
3. **[high]** Captive-portal detection exists (Net.qml:22-40) but apps emit generic errors; Weather keeps stale values with no "as of"; Feeds stores fetched but never shows; Radio wipes list on any error; Mail no offline/empty distinction.
4. **[med]** No 429/503 handling on geocoding/OSRM (curl -sf collapses generic); Feeds retry no backoff; multi-GB model/Flatpak installs on metered connections; Flathub streams no timeout.
5. **[daemon-level]** Landline SIP TLS disables verification and read timeouts (shani-link/.../ua.py:186-193); deploy retries fixed delays and honour no proxy.
Already good: Chronoa cloud LLM exponential backoff with jitter; most API probes bounded; Screenshot OCR fully local.

## VERBATIM: Search and navigation depth

1. **[high]** Feeds and Mail invisible to launcher global search (Launcher.qml:370-489); contact search only name/phone/email; event search title-only; content search hardcodes folders instead of Settings.data.searchFolders.
2. **[high]** `>` is raw sh -c runner, not a command palette — no fuzzy command list, descriptions, recent commands, argument completion.
3. **[high]** Matches never highlighted in launcher results despite Common/HighlightText.qml; no saved/recent searches.
4. **[med]** Launcher category chips disappear once query typed (keyboard users lose filtering); Escape closes rather than unwinds; no shared document MRU; no focus-last-workspace keybinding; no named-workspace-by-name navigation; scratchpads no cycle/list.
5. **[med]** Chronoa handoff from launcher result passes only query or file path — selected contact/event/note identity discarded.

## VERBATIM: Theming and visual customization depth

Correction: automatic dark schedules (time-of-day AND sunrise/sunset) already exist (Appearance.qml:28-73) — not a gap.
1. **[high]** Font hinting/antialiasing hardcoded (Appearance.qml:130); no independent lock-screen wallpaper; accent one global token with fixed alphas; bar height/opacity constants.
2. **[med]** No online wallpaper sources/transition choice; slideshow/live wallpaper global while still wallpapers per-monitor; bar widgets toggle but not reorder (control-centre tiles do); icon/cursor themes no preview and require restart; no theme export/import; focus ring fixed #ff7f50 in session.kdl rather than Theme.accent; no window-border toggle; matugen templates hardcoded to one GTK template; no wallpaper-specific day/night schedule; font sizes fixed 10-14; no compact/dense bar mode.
Out of scope: server-side titlebars, per-window transparency, colour filters/gamma/HDR, pointer effects.

## VERBATIM: Performance and scalability

Measured: 348 QML files, 143 services, 75 bridges, 191 Timers (54 repeating), 86 `running: true` bindings (72 eager Processes), 64 ListViews (16 without reuseItems/cacheBuffer), 473 Repeaters, 272 execDetached calls.
1. **[high]** Viewer thumbnail strip decodes every image full resolution no sourceSize/asynchronous (Viewer.qml:494-510); main image synchronous uncapped (:92-104); wallpaper preview likewise.
2. **[high]** Launcher whole app grid via Repeater rather than recycling GridView; 18 ListViews no reuseItems/cacheBuffer; live notifications unbounded; Feeds read-state map and Photos metadata never prune deleted items.
3. **[med]** 72 eager Processes at startup (~40 one-shot command -v probes); Photos re-walks Pictures every open; Music library re-walks every open; 10s /proc/*/fd polling fallback in Privacy.qml:42; one wtype process per OSK keystroke; two always-on 10-minute timers in Tasks/Agenda.
4. **[med]** dev/shell-test.sh has real budgets but no large-data fixture and 30s idle window cannot catch 10-minute timers.
Already good: Common/Proc.qml debounces/times out; Files.qml persistent worker with watchdog; process/stats polling gated on visibility; app windows LazyLoaded.

## VERBATIM: Input methods and multilingual text entry

Handwriting genuinely implemented (WritePad.qml, bridge/handwriting.py).
1. **[high]** Plain TextFields no undo/redo; OSK no emoji page, no paste key, no key repeat; no IME preedit/candidate integration; Indic handwriting silently degrades to English OCR and only tesseract-data-eng ships.
2. **[med]** No long-press accent popups; pre-desktop keyboard Latin-only; voice typing tap-to-toggle no push-to-talk; no spellcheck, password autofill, autocapitalize hints, deterministic text expansion or per-app IME profiles; no one-handed OSK mode; no swipe typing.
3. **[low]** Mixed-script font fallback relies on fontconfig but no render test; switch access absent (eye/head pointer compositor-level).

## VERBATIM: Notification and alerting depth

1. **[high]** resident hint ignored so persistent popups auto-expire; low-battery (15%) and peripheral alerts normal urgency suppressed by DND while only 7% critical; no call/message or repeat-caller DND exceptions; snooze relative-only, loses actions/urgency, no list UI, re-delivers up to 20s late after boot.
2. **[high]** No per-app sounds/volume/vibrate, no escalation, no unified silent gate across sound/flash/speech, no storm coalescing. Lock-screen notifications inert Text rather than actionable NotificationCards.
3. **[med]** Any app can self-declare urgency 2 bypassing DND/rules/silent-apps; DND dndUntil bypassed by automations; history capped at 50 with no export/TTL; Backup/PdfSigner/VoiceRecorder/Camera completion notices no "open result".

## VERBATIM: Test and docs consistency after mass pass

1. **[critical]** shani-shell PKGBUILD was 9 commits behind, would install package with none of new features — repinned to 4772748, pkgrel=40. Added deps picocom, smartmontools to PKGBUILD and chown, renice to dependency map in c692899.
2. **[fixed]** 77 stale [open] markers flipped to [built — mass pass]; integration/deps note corrected; check counts 700+→800+.
3. **[open]** 11 of 21 test_gap_*.py files pure source-string assertions that cannot catch runtime breakage; hi.json/mr.json remain 1525 keys while template.json grew to 3684 — 242 new strings ship English-only.
4. **[fixed]** data/whats-new.md and FEATURES/README app catalogue updated with mass-pass capabilities.
5. **[open]** No test asserts PKGBUILD pin tracks HEAD; no translation-catalog parity test. Podcast enclosures are metadata + link, not download queue.

## VERBATIM: Advanced notes / files / calendar / media / shell utilities (pass 10)

Advanced Notes: diff-before-restore; note templates; daily/periodic notes; outgoing-link index + orphan detection; tag index/graph/nested tags; search operators; regex toggle + saved searches; pin/favorite + colour; nested notebooks; templater variables; kanban/table view; HTML export with real Markdown+CSS; styled PDF; static-site publish; block references; YAML front matter; sync conflict resolution; plugin API. Top: #1–#5 then #6/#8.
Advanced Files: no per-file Previous Versions from btrfs; search no operators/regex; batch rename numbering-only; no bulk permissions/ACL/xattr; folder sync one-way; archives not navigable as folders; stars one bit; search silently caps; no saved searches; bookmark aliases unwritable; per-tab history actually global; no content search inside archives; no compare of two archives; no bulk resize/convert; no extract-to-multiple; Exif tokens absent.
Advanced Calendar: editing recurring event destroys custom RRULE (data loss); no custom patterns; no recurrence preview; no agenda-list view; control-centre mini-month no events; location inert; no date-range export; no calendar groups; recurring tasks 3-value sidecar; no tasks↔calendar; no per-occurrence exceptions; no free/busy; no busy/tentative status; no working hours; no time blocking; no subtasks; no publish-link; no travel buffer; no unified reminder list.
Advanced Mail: 24 composition/organization gaps (recipient autocomplete; signature; read receipt; priority; reply-to; send later; HTML compose; spellcheck; drag attachments; preview; CID images; large-file; filters; quick filters; saved searches; snooze; tags; quote collapsing; add to contacts; RSVP in message; email→event; undo send; draft autosave; full keyboard nav).
Advanced photo/video/media: EXIF editor; subtitle burn-in; perceptual dedupe; transitions; tone controls; colour correction; speed ramping; before/after; non-destructive edits; slideshow music; presets; geotag/map; smart albums; scrobbling; recommendations; bulk metadata; audio mixing; N-up print; social share.
Shell-specific utilities (Tour, Quick Look, PinCapture, ScreenSaver, AmbientLight, TabletMode, Shelf, Housekeeping, Smart, SmartReplies, WritingTools, Ring): Skip indistinguishable from completion; Quick Look no zoom/PDF nav/seek/share; PinCapture triple-open bug; one pin no zoom; screensaver never over lock; photo mode no curation; ambient no-sensor overwrites brightness with clock curve; sensor hotplug undetected; lid state dead; parked entries never validated; recents hardcoded; SMART warning re-notifies forever; Smart watcher no opt-out; SmartReplies maps unbounded; WritingTools replace destroys clipboard; Ring hardcoded contents; keyboard/a11y thin.

## VERBATIM: Data portability formats / FilePicker / CLI (pass 11)

Data portability capability matrix for Contacts, Agenda, Feeds, Mail, QuickNotes, Photos, VideoTrimmer, VoiceRecorder/Music, Passwords, Tasks, Terminal, WebApps, Clipboard, Screenshots with top-3 missing formats each; 22 ranked gaps (Contacts CSV, vCard 4.0 hardcode, LDIF; Terminal OpenSSH config; VoiceRecorder MP3/AAC; VideoTrimmer EDL; QuickNotes HTML/PDF; Music playlists; Calendar export; Mail .eml/mbox; Photos XMP/Takeout/export-selection; Feeds JSON Feed; Tasks todo.txt; WebApps import/export; Screenshots formats).
FilePicker: picker is thin overlay; 20 gaps (no search though model supports; no overwrite confirm; wildcard MIME filters degrade to show-all; no save feedback; no drag from picker; portal not modal to requesting window; no preview; no Recent/Starred; no show-hidden/sort/view; no Ctrl+L; writable hint dropped; no default extension; no create folder; multi-select offered when false; Open With broken; no reveal folder; can't set default; read errors look empty; keyboard gaps; no recent save locations).
CLI/Terminal: shani media next/stop/previous/toggle silent no-ops (fixed); advertised --json doesn't exist; most app operations no CLI verb; no dry-run/verbose/config/version; unchecked args; wiring test can't catch arity; Connect spawns TTY-less process; no per-app terminal; monospace font never reaches terminal; transparency hardcoded; only foot themed; SSH host groups promised absent; no ~/.ssh/config import; no multiplexing; no host-key management; tunnel list no liveness; agent forwarding config-only; key list display-only; RSA-only; snippets clipboard-only; no command-completion notification.

---

# Fourth pass — VERBATIM agent reports

## VERBATIM: Cross-app integration and data portability

Tier 1 — high value, cheap:
1. **mailto: has no handler** — dev.shani.Mail.desktop has empty MIME list (bin/shani:524-525), niri skel no default, XF86Mail falls to browser. Register x-scheme-handler/mailto + message/rfc822.
2. **Share sheet no targets into our own apps** — Services/Share.qml:20-35 only KDE Connect/Bluetooth/LocalSend/QR/xdg-email/clipboard/gio; Photos no share action. Add Notes/Photos/Editor targets.
3. **Copy-path copies plain text, not text/uri-list** (Viewer.qml:287, TerminalAppWindow.qml:328), cannot paste as file. Mail compose/Text Editor/Photos no inbound DropArea.
4. **Apps never write recently-used.xbel** — Launcher recents one-way from GTK. Calendar ICS import but no export. Notes .md and Contacts .vcf no default associations.
5. **geo:/web+*/obsidian:///file:// no registration or dispatch policy.** Desktop entries emit no Actions=.
6. **No portable data bundle** ("take my data to another OS") — Photos/Mail/Passwords no export UI.
7. **Mail cannot attach a file** — send() takes no file list; Share's Email target shells xdg-email bypassing Mail.
8. **Portal backend implements only FileChooser** — Email/Share/SendFlatpak intents bypass shell. Rich-text/file-URI clipboard formats dropped.
9. **No notification→file affordance;** portal/share handoffs call Ui.closeAll() discarding surface; Files bookmarks no import/export; no shared cross-app session document registry; skel default-app lists drift across editions.
Stale: "Files can't drag out" is false — FilesPanel.qml:863,985,1197 does drag out.

## VERBATIM: Multi-user, family, guest, enterprise/MDM

Already built: per-user settings/screen-time, app blocking via malcontent, guest on/off, usershares, current-grants privacy dashboard, fleet agent with inventory/signed remote exec.
Feasible gaps: screen time advisory only (no enforced caps); no bedtime/downtime schedule; no weekly/monthly report or export; parental filter set outside shell; no approval/ask-a-parent flow; no per-user web/content filtering; no privacy access timeline; no bulk revoke/app-data deletion; no "why does this app need X" rationale; no simplified/caregiver mode; guest has no rules; no kiosk/single-app mode; no settings-profile copy between accounts; no child-visible weekly digest.
Needs server/daemon: MDM enrolment/policy plane, remote wipe/lock, signed configuration profiles, per-user certificate management, enforced signed settings, trustworthy access log, cross-account parental supervision, guided access/switch control, family account layer (CalDAV/CardDAV/IMAP services), enterprise inventory surface.

## VERBATIM: Hardware and peripheral depth

1. [H×M] Bluetooth codec choice (LDAC/aptX/AAC/SBC) — no org.bluez.MediaTransport1 reference anywhere.
2. [H×M] USB device blocking — no usbguard reference.
3. [H×M] General key remapping/layers — InputConfig.qml:15-32 writes only xkb options.
4. [H×M] Per-app camera/mic permission for native apps — SettingsAppPermissions.qml governs Flatpak portals only (partly OOS).
5. [M×E] Camera hardware privacy switch state — Privacy.qml:17-20 infers from kernel module, not actual switch/LED.
6. [M×M] Camera controls (focus/exposure/zoom/pan/tilt) — Camera.qml:87-89 uses cam only to select index.
7. [M×M] Microphone AGC/gain — SettingsSound.qml:273-280 only RNNoise toggle.
8. [M×M] Audio loopback — no module-loopback/null-sink in shell.
9. [M×E–M] Per-app power profiles — GameMode.qml:26-29 hardcodes fullscreen game → performance.
10. [M×E] Thermal sensor depth — SysStats.qml:119-122 reads single CPU hwmon.
11. [M×E] EDID/panel info — Displays.qml:238-239 keeps only make/model/physical mm.
12. [M×E–M] Extended printer options — SettingsPrinters.qml:189-191 hardcodes media/duplex/colour.
13. [M×M] Bolt device management UI — Thunderbolt.qml:23-37 enumerates/prompts on arrival only.
14. [M×M] UPS depth — bridge/ups.py:35-51 reports only first UPS and six variables, no graceful shutdown.
15. [L–M×M] Per-sink audio delay (lip-sync) — Audio.qml no latency property.
16. [L×E] Sound theme/scheme — SystemSounds.qml:13 hardcodes freedesktop path.
17. [L–M×M] Named multi-monitor arrangement profiles.
OOS: virtual displays, overscan, mouse accel threshold, fan curves, USB gadget modes, per-output HDR/gamma/colour filters, Sticky/Slow/Bounce Keys.

## VERBATIM: Missing app categories

18 categories: Podcasts (Q), audiobook mode (Q), IRC (Q), database client (Q), teleprompter (Q), network tools (Q), health/fitness (Q+D), startup manager (Q), scheduled tasks (Q), offline dictionary (Q), VPN client (partial), cloud storage (D/S), system restore (partial), video conferencing (WebApp), e-book reflow (partial), NFC (H), Emergency SOS (S+H).
Out of scope: Find My, wallet/payments, iMessage/FaceTime/iCloud, native app store, browser/office/torrent/VM/games (Flatpak-only), remote desktop control, NFC/SOS.

---

# Third pass — VERBATIM agent reports (from original audits)

## VERBATIM: Unaudited utility apps

Archive Manager: gaps delete/rename member, route .jar/.apk to zipadd, open member in own app, integrity test, add to 7z/rar/ISO, progress, comments. Bugs: appendable includes jar/apk but branch uses zipadd only for zip; zipadd.py stores ../outside.txt for files above archive folder; zipadd.py names no caller.
Calculator: gaps DEG/RAD/GRAD, variables+Ans, mod/integer division, hyperbolic, log(x,base), history persistence, currency/date conversions, copy expression. Bugs: Ui.calculatorTab written but never read at startup; Base ▸ button inert; charCode uses UTF-16 charCodeAt(0) vs fromCodePoint.
Clocks: gaps weekday repeat/one-shot/snooze/sound, ringing panel, custom timers/multiple, per-lap deltas, in-app city search, sunrise/sunset, state persistence, shortcuts. Bug: lastFired single minute string so alarm added for already-fired minute silently missed.
Characters: gaps browse starts at ASCII punctuation not symbols/scripts, favorites/recents, Unicode-block browsing, insert-into-last-app, multi-codepoint emoji skipped, copy as U+/HTML/decimal, glyph detail, font preview. Bug: characters.py:203 claims browse shows symbols first but returns entries[:limit].
Fonts: gaps family/style search (400-style cap), uninstall, drag-and-drop, license/glyph grid, .ttc face list, Settings handoff, side-by-side, recents. Bugs: percent-encoding in install path (fixed), installFont silently overwrites.
Maps: gaps limit=1 geocoding, transit, live traffic, offline maps, map style, typed start marker/waypoints, reverse geocoding, alternative routes, keyboard pan/zoom. Bug: routeUrl always uses Location ignoring typed fromLat/fromLon (fixed).
Disk Usage: gaps Rings chart, scan progress, exclude config, in-app chooser, hardlink double-count, preview, used/free bar. Bugs: dir_size walks every subtree synchronously per child; enter()/back() don't clear marked (fixed).
Document Scanner: gaps batch/duplex, post-scan crop/rotate, page reorder/merge, scan-to, scan-area, per-device options, OCR, history. Bugs: scanErr collected but never displayed; --resolution not universal SANE option.

## VERBATIM: Communication/apps

Logs: "Show raw entry" button closes details; priColor() defined never used; no priority/unit/boot filters; fixed -n 200; no export; search misses PRIORITY fields; no new-error notification.
Password Generator: no exclude look-alikes, custom length, word count, entropy readout, save to keyring, GPG actions, clipboard auto-clear. RNG sound (secrets); wordlist missing silently emits random string.
Authenticator: UI cannot set digits/period/algorithm (bridge can); no edit/rename; no export/backup (lost keyring loses all tokens); no search/sort; no icon; clipboard not cleared; refresh tick can miss rollover. Secrets in GNOME Secret Service (good).
Nearby: cancel unwired (fixed), text sharing, no persistent trust store, fixed receive location, rename, history, folder send. Security: TLS CERT_NONE, fingerprint from unauthenticated multicast.
Converter: fade/artist/speed unwired (fixed), per-job options wrong, output-folder choice, metadata strip, no cancel. Invalid numbers silently coerced.
PDF Signer: only current page saved — one-page PDF destroys rest (fixed); no real cryptographic signature; no drag-to-place; no rotation/opacity/multi-signature; no AcroForm fill; no placement undo.
Kundali: timezone always UTC (appends Z) — wrong Lagna (fixed); nine bridge commands unwired; no visual chart; no city search; no export/history; hardcoded Lahiri; malformed ISO with seconds.

## VERBATIM: Messages/Calls/Phone

Architecture: GTK4 shani-link owns Messages/Calls; QML shell has entry points and modem dialog.
Gaps: conversation search; inline Reply on text notifications; group threads; image attachments; SMS backup/export; drafts; speed dial/favorites in shell; call-waiting UI; tie recordings to caller; delivery/read status.
Security: messages not E2EE, bodies echoed to notify-send; positive: bidi control chars stripped, switches default off.
Dead: PhonePanel.add_tab() empty stub; openRecentCalls() opens Calls tab.
Impossible: real SMS/voice without modem/paired phone; iMessage/FaceTime/RCS; typing indicators/read receipts/reactions; visual voicemail; E2EE for SMS; MMS picture receive.
Already built: call history with duration, hold/swap/merge landline, two-sided recording with consent, SMS OTP copy and Reply.

## VERBATIM: Accessibility (general)

"Accessible by default" overstated. 20 gaps: no live regions; custom controls no AT-SPI name/role; slider value not exposed; verification claim thin; Super+Alt+S absent in running session (fixed); Theme.faint fails AA; accent on accentSoft fails AA; captions not accessible output; error message claim overstated; muted state colour-only; touch targets inconsistent; no continuous text size; no focus traps; Escape missing in Mail/Feeds/Processes; no headings/landmarks; focus ring 1px colour swap; IME hints only for secrets; no RTL mirroring; one unguarded animation; app-menu AT-SPI best-effort.

## VERBATIM: Security/i18n/ecosystem

Security: hook placeholder injection (fixed), QR world-readable path (fixed), files.py chmod follows symlinks, WebApps safeUrl undefined (fixed), stale desktop entries glob quoted, SettingsPage fake chips (fixed).
i18n: greeter no translation, two catalog systems, English plural via %2, no placeholder parity validation, 83 unwrapped literals, two substitution mechanisms.
Ecosystem: no CONTRIBUTING, no IPC reference/stability contract, no man page/completion, undocumented LauncherEntry D-Bus, settings pages hardcoded, no theme-pack API, no CI config.

## VERBATIM: Capture tools

Screenshot: region/window capture, all-monitors, history browser (encrypted captures never listed), OCR preview, configurable dir, pin zoom/fit. Bugs: PinCapture claims move/resize but fixed window; scroll-capture manual mode documented but absent.
Recorder: pointer toggle, delay, single-window, container choice, cancel, max duration, mic meter.
Color Picker: no picker window, recents never rendered, colour wheel, copy-as formats, sample from image. Bugs: claimed clipboard copy never happened (fixed), picked signal no listener, dead code!=0 branch.
Ruler: ratio never assigned (fixed), diagonal/angle, ticks, saved measurements, units, arrow nudge, loupe. Bugs: dead straight property, grim captures all outputs vs one screen, temp PNG never deleted.
Lens: QR action types beyond http/copy, OCR language choice, editable OCR text, TSV structure, history, keyboard region. Bugs: save hardcodes .png for jpg, openImage no encoding, language regex.
Magnifier: auto-refresh, full-screen mode, inversion, resizable, arrow pan, reset key, cross-monitor.
Captions: history/scrollback, pause/resume, timestamps, font settings, send to Chronoa, language picker. Bug: hh-mm 12-hour filename (fixed), out-of-order captions.
Tour: five raw literals not Tr.t, tourEnabled checked only in shell.qml, no spotlight/capture card/try-it/replay/Back.
Preview: PDF navigation/zoom, metadata, archive extract-one, video seek, share, image zoom/pan; Viewer redo/fullscreen/copy pixels. Bug: PDF cache key md5(path) only (fixed).

## VERBATIM: New apps and session surfaces

Backup: two restore buttons identical (what/restoring dead); CLI restore into new folder only; no progress/cancel, JSON errors swallowed, no verification badge, retention/exclusions/off-site/diff.
Models: API keys never stored (fixed); download announces success on failure and notifies per line; preferred model set before success; GGUF claim false; VRAM unused; no live registry/test-connection/in-window errors.
Studio: busy never cleared (fixed); find expression can never match .desktop under ~/Developer so gio launch dead; no code preview/revision/syntax check/export/privilege warning.
Firewall: newZone/deleteZone use --permanent without --reload; parseZones drops hyphenated keys; interfaces/target parsed but not displayed; presets English; no panic mode/logging/validation.
Passwords: audit never ran (fixed); passkey copy wrong field; passkey-add false success; FIDO2 no commands; locked collections invisible; attribute editing, GPG expiry, import/export, generator handoff.
Greeter: typed password kept on user change (fixed); no translation, IME, auth status, last-layout, user dconf a11y, PIN path, retry countdown.
Setup: 1-char password (fixed); Chronoa setting written from greeter user; auto-join open Wi-Fi without asking; onAuthMessage answers every prompt with password; no hidden Wi-Fi/proxy/restore/encryption/import/telemetry.
Lock: messages raw English; photos accumulate but only newest shown; biometric unlocked() outside password conversation; queued discarded; no session-level lock test.

---

# First pass — the original app-by-app audits

The first pass compared each app against its closest open-source equivalent and produced 5–8 ranked gaps per app with implementation sketches. Those original reports were transferred into `docs/GAPS.md` in the section "Full upstream app comparison — every gap found (Nov 2026)" (158 gaps across 20 apps) and into the curated pass sections above. The three doc-audit agents (shani-shell docs, shani-docs, infra repos) found stale counts, wrong paths, false plugin claims, edition/provider/sync-direction errors, and workflow profile/timeout/secret errors — all fixed in commits 28c49e5, 1a585ab, 8b18653, 3d5da6b, 80139eb. The upstream equivalents compared were: Text Editor→Kate, Notes→Joplin, Calendar→GNOME Calendar, Contacts→GNOME Contacts, Files→Nautilus, Photos→gthumb/Loupe, Viewer/PDF→Evince, Mail→Geary, Feeds→Newsboat, Terminal→kitty, Disks→GNOME Disks, Software→GNOME Software, Processes→htop, Settings→GNOME Settings, MediaPlayer→VLC, Camera→GNOME Snapshot, VoiceRecorder→Vocalis, VideoTrimmer→LosslessCut, Translate→Argos, Weather→GNOME Weather.

---

All reports in this archive are static findings — no runtime, hardware, live network, real daemon or Flatpak verification was available in this environment.
