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
