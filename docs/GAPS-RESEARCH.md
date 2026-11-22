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
