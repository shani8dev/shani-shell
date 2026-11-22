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
