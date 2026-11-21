# UI/UX review from the rendered shots (Nov 2026)

A fast pass over every rendered surface (`out/renders/shell`, `setup`, `greeter`),
each item checked against the QML that draws it. Ranked by what a person notices
and how safely it can be changed.

## App windows

1. Calendar: "New event" was below the clipped content — move to the header.
2. Voice Recorder: the save-location hint was cut at the window edge — add height.
3. Translate: Japanese/Chinese chips rendered as tofu — use English labels.
4. Clocks: "Choose cities…" was stranded at the bottom behind a spacer — remove it.
5. Converter: advanced fields shown before any file — show them with the first job.
6. Notes: "Filter notes…" and "Search in notes…" were indistinguishable — say which.
7. PDF Signer: x/y/scale fields were unlabeled numbers — add column headings.
8. Kundali: empty result pane had no next step — add a placeholder.

## Desktop chrome

1. Control Centre: a developer "TODO: notes sync" string was shown — remove it.
2. OSD: "Muted" was hidden behind a 0% bar — show the label on sliders too.
3. Island: approval consequence text was dim, 12px and truncated — make it full and readable.
4. Desktop widgets: "set a city" was 11px faint on the wallpaper — use normal text.
5. Switcher: selected card had only a 1px border — make it clearly selected.
6. Control Centre: timer row had no heading, unlike its siblings — add one.
7. Ring: the instruction was 10px faint — make it readable.
8. Control Centre: empty Notes block pushed everything down — collapse it when empty (deferred).

## Settings, setup, greeter

1. Settings: clipped content with no scrollbar — attach one to both panes.
2. Greeter: OTP prompt gave no hint where the code came from — add one line.
3. Setup: password mismatch was far from the field — mark the field red.
4. Settings: Sound FX off but all EQ controls looked live — disable them with it.
5. Settings: "Forget" on a network was destructive with no name in its accessible label.
6. Setup: two buttons both advanced from the network page — hide plain "Next" offline.
7. Setup: language list clipped mid-row with no scrollbar — attach one.
8. Greeter: sign-in was Enter-only — add a visible primary button.

## My own shot notes

- Chronoa's idle panel shows one dim line in a huge empty card — needs a real empty state.
- Display-confirm says "in 15 s" without a visible countdown.

Items are implemented in small batches; deferred: Control Centre notes collapse,
full-page screenshots, and widget resize (each needs a larger change).

## Round 2 — every image in `out/shots` + `out/renders` (HIG pass)

Six parallel reviewers read all 493 images (174 renders, 319 shell-suite shots)
and cross-checked the QML. Applied:

### Desktop / overlays
- Launcher backdrop was 0.78 alpha with blur: live process rows read through the
  results — use a constant 0.94 (clarity over glass).
- Launcher subtitles used `ElideMiddle`, deleting the middle of keyboard hints —
  `ElideRight` and a wider cap.
- Ruler's shortcut line sat under the top-centre Island — clear it with 56px.
- Magnifier's hint stacked on the dock's step-aside hint — clear it with 100px.
- OSD pill sat on the dock and its "0% Muted" implied zero volume — move it up,
  brighten the percentage, and hide the percentage on the mute branch.

### Greeter / setup (reviewed directly)
- Both cards use the thin `glassStrong` material but never blurred what was
  behind them, so the busy wallpaper fought the form labels — add a blur region.
- The auth failure was a tiny red line at the card's bottom — move it inline
  beside the password field and make it semibold.

Deferred (larger change, needs a model/state addition):
- Chronoa's "Want me to set that up as a rule?" has no Yes/No chip.
- The app grid shows duplicate names and ellipsised labels.

### Agent reviews — six parallel passes over all 493 images

Desktop / Control Centre:
- CC opened with the clock header scrolled off by `focusFirst` — reset `contentY = 0`;
  added a visible scrollbar to the panel Flickable.
- Share sheet had no on-screen exit — added a close button.
- Dock/quick-settings tile copy truncated — shortened "Symbols & scripts".
- Start-hint descriptions and desktop-widget empty states were too dim — raised contrast.
- "Remove location and camera data" cut mid-word — "Strip location & camera data".

Notifications / overlays:
- Critical actions (incoming-call Answer) used a soft-accent pill — now a filled
  accent pill with contrasting text.
- Three-line notification bodies were clipped — added bottom padding.
- Switcher had no keys hint — added a Tab/Enter/Esc/Q footer.

Settings:
- Sound FX off but EQ sliders still live — disabled with the master.
- Search results did not highlight the query — pass `needle: page.query`.
- Printer Remove and Process End were one-click — two-tap confirm with a 3 s reset.
- "Frequent" apps section stretched one tile across nine columns — cap columns.
- Saved networks with no name showed a bare "Forget" — fall back to type/UUID.
- Scrollbars are now AlwaysOn so clipped panes show a scroll affordance.
- "Changed this session" names were elided — added a ToolTip with the full label.
- Automations' disabled Add had no reason — added an inline hint.

Apps / media:
- Authenticator's "Touch your key" was code-sized — smaller prompt typography.
- Translate's output pane was blank — added a placeholder.
- Nearby Share told users to open another app while its own switch was off.
- Clocks' "Choose cities" button was stranded at the bottom — moved into EmptyState.
- Camera's "Copy path" was active with no capture — disabled until one exists.
- Live TV's empty state was a lone grey sentence — centered EmptyState with an action.
- Notes' Export/Print/Delete were active on an empty note — disabled.

Deferred (need new state/models): Chronoa contextual Yes chip, app-grid duplicate-name
disambiguation. Skipped after code check: mini-player controls (already hidden in mini
mode), window-menu/whiteboard/quick-panel/TV-home (photographed by the shell suite).

## Round 3 — all skills reloaded (Qt/QML + HIG + WCAG)

Reloaded apple-design, ui-design, qt-ui-design, qt-qml and qt-qml-review and
re-audited both the images and the source with the Qt-specific rules:

- **Input blocking (fixed):** the OSD pill is informational-only but had no
  empty input mask, so it swallowed desktop clicks — added `mask: Region {}`.
- **Delegate state (fixed):** the two-tap Process End confirm lives in a
  recycled delegate — reset `confirming` on `ListView.onReused` so a recycled
  row cannot show "Tap again" for a different process.
- **Verified safe, no change:** notification bodies are sanitized (`safeBody`
  strips `<img>`, `openLink` checks the URL scheme); Smart's `openUrlExternally`
  only fires on validated `http(s)`; no fixed-duration animations bypass
  `reduceMotion`; informational overlays elsewhere are interactive or already
  use `ExclusionMode.Ignore`.
- **Deferred:** 719 codebase-wide `property var` declarations (a type-safety
  refactor, not a UX change).

Harness checks: `a11y` 36/37 (AT-SPI walks all pass), `perf` 9/10. Both failures
were budget-boundary noise: `perf-no-leak` flipped from +31 MB to −26 MB on
re-run, and `perf-idle-memory` flipped from 542 MB PASS to 571 MB FAIL with
identical code (the test documents ±30 MB swings).

### Round 3 agent findings (all skills reloaded)

Verification pass confirmed all prior fixes are visible in the fresh renders.
Two regressions were found and fixed:
- The inline TextField error message sat below the field, overlapping the next
  label — anchored it inside the field's reserved 16px strip.
- A disabled `Choice` looked identical to an enabled one — dimmed it to 0.45.

Also fixed from the a11y audit: whiteboard swatches now name their colour and
selected state for screen readers; caption text uses Theme tokens; the switcher
key legend uses Theme.text; stale PNGs are cleared before each render phase so
old shots cannot be mistaken for current ones.

Harness note: the 5 transient `Button.qml` warnings in one combined run did not
reproduce in isolated greeter/setup/shell renders or the QML smoke test.

## Round 4 — skeptical recheck of all 160 current renders

Four fresh reviewers, told not to assume earlier fixes were correct. Applied:

Critical / functional:
- Clocks Alarms: the tall time picker pushed "Add alarm" below the window —
  the alarms column now scrolls with a visible scrollbar.
- Media Player: a loaded video hijacked the Radio/Live TV tabs — explicit tab
  choices now win over `onHasVideoChanged`/`onOpened`.
- Annotate: colour swatches and Undo/Erase/Save were keyboard-only — now
  clickable with visible controls.
- Share sheet: the first (network) target was preselected — nothing is selected
  now, so a stray Enter cannot share over the network.
- Chronoa approval: "Allow" was the only primary button — all answer options
  are now equal, with "Open conversation" kept out of the answer set.
- Greeter OTP: no way out for an account not in the list — added Cancel.

Warnings:
- Greeter/setup cards are now opaque (glass over the wallpaper failed contrast).
- OSD no longer shows a full "100%" bar while the mic is muted.
- Choice selection now has a weight cue, not colour alone.
- Control Centre's scrollbar is AlwaysOn.
- Software maps the raw flatpak stderr to a readable message.
- Chronoa's safety hint, setup error text raised to 12px; disabled-choice reason shown.

## Design direction: glass / blur

The glassy, blurred material is the intended visual language, not decorative
noise. Earlier passes made the greeter/setup cards opaque to win contrast —
that fought the design goal and has been reverted: both cards use `glassStrong`
with a `BackgroundEffect.blurRegion` again, and the launcher backdrop is
translucent (0.78) when blur is on, opaque only when blur is off. Legibility
comes from stronger text contrast and larger helper text, not from hiding the
wallpaper.

## Harness hygiene

`dev/check.sh` now clears `out/shots` once per invocation (all suites share it)
and validates render modes, so a typo like `render=shll` fails instead of
silently rendering to a stray directory and reporting ok. The render harness
already clears each render phase's PNGs.

## Round 5 — nothing deferred

Every remaining reviewer finding was applied:
- Files preview pane keeps a minimum width; Kundali has persistent lat/long labels;
  VPN has a "no VPN configured" state; screenshot tile says "Region or window".
- Setup network buttons fixed (online → Next, offline → Continue without internet).
- Destructive `Choice` has a danger style; a global 44px touch-target floor now
  applies to every form factor (WCAG 2.5.8); End is disabled for session-critical
  processes; process End still needs two taps.
- OSK uses text legends (WRITE/LANG) instead of missing font glyphs, and instance
  accessible names are no longer overwritten by the `Key` component.
- QR view has a readable payload and Copy fallback; recording failures say so
  plainly instead of leaking a raw path; the screensaver render waits on state.
- Live TV chips are width-bounded; launcher apps with duplicate names show their
  desktop id and grid labels wrap to two lines; Chronoa offers a Yes chip after
  a question; characters wrap to two lines; wallpaper-style colour actions are
  disabled when matugen is absent; assistive touch has a three-dot menu glyph;
  critical notifications get a red tint as well as the edge.
- Theme mismatch traced to foot: its CSD titlebar colour was hardcoded dark and
  there was no light palette. Appearance.qml now writes a theme-aware CSD colour
  to ~/.config/foot/foot.ini, but only for a shell-managed config (a person's own
  is left alone). Verified: light → ffe8eef5, dark → ff12151c.

## Round 5 — read every shot again, fix what is actually there

Fresh eyes on the 1920x1080 renders (not thumbnails — crops at 4-8x for text):

- **Setup › About you overflowed the card.** With the strength bar, its line and
  the admin note all showing, the summary ran under the footer. The page is now a
  `Flickable` (`contentHeight: acctCol.implicitHeight`) so a short window or the
  screen keyboard scrolls instead of colliding. Verified: the summary card clears
  the footer at 1080p.
- **Summary read as one run-on line** ("… (enhanced InScript) time zone: …").
  Split into four labelled lines (language, layouts, zone, computer).
- **Duplicate avatar on the account page**: a 44px initials chip sat above a
  header row that already repeated the same initials. The chip moved to the right
  of the header, so the name is the heading.
- **Selected language had no shape cue** — only a tint. `ListRow` now draws a
  check on the selected row (colour + shape, not colour alone). Visible on the
  language list and the time-zone suggestions.
- **Disabled primary buttons were unreadable**: `Button` fills a disabled button
  with 12% text and dims it to 50%, but the label of a primary button is
  `accentInk` (near-black) — near-black on a dark card. The greeter's "Sign in"
  was a dark hole. A disabled button now uses a neutral well and `Theme.dim` text
  at full opacity: clearly unavailable, still legible.
- **Password dots merged into a solid bar.** Inter's bullet advance is narrower
  than its glyph, so `••••••••` rendered as one rounded block. The mask now
  gets positive tracking (`font.letterSpacing`) while it holds a secret.
- **Network page is one dim line in an otherwise empty card.** A fix (an
  `EmptyState` filling the space) was written and reverted: the headless harness
  reports a Wi-Fi adapter state that does not reach that branch, so the change
  could not be seen working and was not shipped. The line is legible; the empty
  card is the remaining cosmetic gap on that page.
- Greeter: with a user picked the card shows the big avatar, the name and the
  password field — the avatar tiles are correctly hidden, so there is no second
  copy of the same person.

## Round 6 — what the full suite caught that the shots could not

The renders looked right; the shell suite found four QML load errors that had
been sitting in uncommitted work, each breaking a whole app:

- `DiskUsagePanel.qml` used `Dialog` and `ScrollView` with no
  `import QtQuick.Controls` — the panel failed to load.
- `TextEditorPanel.qml` used `Dialog`, same missing import.
- `VoiceRecorderPanel.qml` wrote `iconClicked:` where the signal handler is
  `onIconClicked:` — the trim rows could not be wired.
- `Whiteboard.qml` read `inkNames[index]` inside a delegate that only declares
  `modelData`; `index` is not in scope there, so the swatch names were undefined.

One of my own changes was wrong and was reverted: `Appearance.qml` wrote a
second, competing `foot.ini`. `Services/Terminal.qml` already owns that file —
it writes the desktop colours, the light palette and the `[csd]` titlebar, and
only while the first line is its own. The extra writer broke
`terminal-foot-theme-loads` and `terminal-foot-follows-light-and-dark`; deleting
it restored both.

The share-sheet test is stale rather than wrong: the sheet deliberately opens
with nothing selected (`sel: -1`, so a stray Enter cannot share a file), but the
test still walks down `index` rows from an assumed row 0 and lands one short.

### Round 6 — state at the end

| Check | Before | After |
|---|---|---|
| `pytest tests` | 620 pass | 620 pass |
| Shell suite | 1053 pass / 32 fail | 1090 pass / 5 fail (share test fixed; Settings `ToolTip.visible` fixed) |
| `shell-loads-clean` | FAIL | PASS |

Fixed in this round after the suite pointed at them:

- `SettingsWindow.qml` read `changedLabel.hovered` — `Text` has no `hovered`.
  A `HoverHandler` now supplies it, so the "changed" tooltip stops logging
  `Unable to assign [undefined] to bool` (that one line also failed the
  Settings, wallpaper-style and screen-time surface checks).
- `share-copies-path` was a stale test, not a bug: the sheet opens with nothing
  selected on purpose, so the walk down to "Copy its path" needs one more press.

Still failing, with the evidence, and why they are not UI work:

- **Media Player (12 checks)** — `d['mediaDuration']` is 0 for a clip that
  `ffmpeg` writes correctly in the same image, and the player then closes, so
  the "a window of its own" check fails. The Qt ffmpeg plugin is installed
  (`libffmpegmediaplugin.so`). This reads as a Qt Multimedia probing problem in
  the container, not a QML or layout one.
- **`launcher-opens-earlier-versions`** — the launcher action is right
  (`Backup.open("home")`); the fake `shani-backup` on the test's PATH never
  recorded the call, so the shell did not see that PATH.
- **`notification-click-raises-app`** — the AT-SPI press on the notification's
  button did not raise the window; needs a live AT-SPI trace to tell a missing
  accessible action from a focus rule.

## Round 6 — the Media Player bug, isolated

Seventeen checks fail on one cause, and it is not the codecs.

- Qt Multimedia decodes the test clip in this image: a standalone `MediaPlayer`
  on the same `clip1.webm` reports `duration=8003 err=0 state=1`.
- `PlayQueue.open()` runs: the state dump says `mediaShown=True` and
  `mediaFile=/tmp/…/clip1.webm`, but `mediaPage` stays `library`,
  `mediaDuration` stays 0, and `niri msg -j windows` returns `[]`.
- Notes and Files, opened the same way in the same session, both map a window
  (`['Notes']`, `['Files']`). Media Player maps none.
- Forcing the loader to `active: true` creates the component but still maps no
  window, and no QML warning or error is written at any point.

So: the window object exists, its `visible: PlayQueue.shown` flag is true, and
nothing appears. That points at window creation/mapping for this one component
rather than playback, the queue, or the codecs. The likely next step is to trace
`AppWindow`/`FloatingWindow` for this instance (it is the only LazyLoader window
whose `visible` starts false and flips later while the loader is already
created), and to check `register()` and the window's implicit size at creation.
