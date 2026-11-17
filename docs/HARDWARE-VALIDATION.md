# Hardware references and verification

Reviewed 2026-11-17 from the upstream sources below. These projects provide
working implementations, device data and test methods—not certification of
ShaniOS. We have not reproduced their physical-device tests in this session.
See [FORM-FACTORS.md](FORM-FACTORS.md) for the feature backlog.

## What to reuse

| Area | Primary references | Evidence available upstream | Shani approach |
|---|---|---|---|
| Handheld input | [InputPlumber usage](https://shadowblip.github.io/InputPlumber/usage/) and [source](https://github.com/ShadowBlip/InputPlumber) | Device-matching YAML, capability maps, D-Bus API, built-in device tester, event/target inspection | Keep InputPlumber as input owner; consume D-Bus events and use its mappings rather than duplicate HID drivers |
| Handheld hardware | [HHD device list and calibration](https://github.com/hhd-dev/hhd/blob/master/readme.md) | Named device support and exceptions; gyro calibration using Steam and an actual game; volunteer testing described | Reuse device-specific knowledge and test procedures; do not run two competing controller owners |
| Power/thermal control | [PowerStation](https://github.com/ShadowBlip/PowerStation) and [HHD ALIB notes](https://github.com/hhd-dev/hhd/blob/master/alib.md) | D-Bus CPU/GPU/TDP interfaces; device-specific AC/DC and thermal behaviour | Discover capabilities and read back changes; do not copy another model's limits or raw SMU/ACPI commands |
| Touch, pens, switches | [libinput tools](https://wayland.freedesktop.org/libinput/doc/latest/tools.html) and [test suite](https://wayland.freedesktop.org/libinput/doc/latest/test-suite.html) | Kernel-event capture/replay; device fixtures; uinput tests; pressure/quirk diagnostics | Record failing physical gestures, turn them into regressions, then validate through the compositor and QML |
| Tablet identification | [libwacom](https://github.com/linuxwacom/libwacom) | Model capabilities, built-in tablet metadata, tools to identify missing device descriptions | Use metadata to inform screen mapping; libwacom does **not** supply the input driver |
| Recorded-device CI | [umockdev](https://github.com/martinpitt/umockdev) | sysfs/udev/hotplug, evdev/ioctl, USB and modem record/replay examples | Use sanitized captures for bridge regressions; mocks are not proof of firmware or physical input behaviour |
| AirPlay reception | [UxPlay](https://github.com/FDH2/UxPlay) | Upstream lists tested Linux/macOS/BSD systems and Raspberry Pi models; GStreamer sink/decoder and security options | Optional, rootless receiver with PIN/access control; test a real sender, audio/video and teardown |
| Remote-desktop tests | [wayvnc integration suite](https://github.com/any1/wayvnc/blob/master/test/integration/README.md) | Real client keystroke injection and output-add/remove tests under Sway | Reuse the **test pattern**; do not assume a wlroots server works with niri's protocols |

### Source revisions observed

Record the revision when importing a mapping, adapting code or reproducing a
test. The documents were read from the default branches; these were the latest
revisions returned by GitHub during this review:

| Repository | Revision |
|---|---|
| ShadowBlip/InputPlumber | `6aca9202fb8dfd6f31241c3f98b72df4a775c1a1` |
| hhd-dev/hhd | `180f0cd8515787789ce82a8d8a116076c36c98a6` |
| ShadowBlip/PowerStation | `9799ca99cc2bc87aaeb66f63f326eae8c2eb1aa5` |
| FDH2/UxPlay | `48f5ce47c9ef694afccfac907c9e8828329657fe` |
| linuxwacom/libwacom | `fea1650d06a31a203d0ccc3e7fa9a1bbf9dae117` |
| martinpitt/umockdev | `73f1a1f4e9343c698edca531b4fd0db673ad0635` |
| any1/wayvnc | `54a775f88036a8764756dde3818177af94fe3e0c` |

libinput documentation reports version 1.32.0. The installed image's version,
not the website's version, determines which commands and quirks are available.

## Immediate correction: handheld quick-panel access

InputPlumber documents:

- NONE (0): no interception.
- PASS (1): only Guide is forwarded; pressing it switches to ALL.
- ALL (2): events are forwarded to the overlay, not the game.
- GAMEPAD_ONLY (3): gamepad events are intercepted.

Therefore a dedicated ⋯ button cannot be assumed to reach the shell directly
while a game owns the controller. Shani now also offers **Guide → Start**:
Guide opens home and borrows the pad, Start opens the quick panel, Start again
returns home, and Guide returns the pad to the game. The existing dedicated
button still works where a device mapping forwards it.

`dev/shell-parts/handheld.sh` checks that PASS keeps the quick button in the
game and exercises the fallback through the D-Bus stand-in. A physical test
must additionally prove that input does not leak into the game.

## Repeatable physical-device checks

Run these on a designated test device or isolated graphical seat. Do not
inject events into the developer's live desktop. No commands below grant
permission to change host hardware automatically.

### Handheld controller, gyro and resume

1. Record model/DMI, BIOS, kernel, InputPlumber version and loaded device profile.
2. Inspect with upstream's `inputplumber devices list`, `device <id> info`,
   `device <id> targets list` and `device <id> test`; confirm syntax with the
   installed version's help.
3. In a real game, check PASS → Guide → ALL → close → PASS. Record both the
   shell action and whether the game received unwanted input.
4. Exercise Guide → Start, direct ⋯ if mapped, every face button, sticks,
   triggers, back buttons and controller hotplug.
5. Follow HHD's axis procedure: compare Steam's calibration glyphs, test yaw
   and roll in a first-person game, then report axes/inversion with make/model.
6. Repeat after suspend, with AC connected/disconnected and an external display.
   Check that orientation and input ownership recover.

Never install HHD alongside InputPlumber as a second controller owner merely
to obtain another UI. Reuse upstream data with its licence and attribution.

### Touch, pen, tablet-mode switch and rotation

1. Inventory the physical device and its udev/libinput properties. Note that
   `libinput list-devices` reports defaults, **not the compositor's configuration**.
2. Capture a short reproduction using `libinput record` for the affected
   event node. Record pen and touch together when testing palm rejection.
   Redact serial numbers and review traces before sharing; never record secrets.
3. Replay only in an isolated seat/VM configured for virtual input. libinput's
   uinput suite can interfere with a live session and upstream explicitly says
   its hardware suite is unsuitable for ordinary containers.
4. Test slow swipe vs swipe-and-pause, cancellation, pinch, two simultaneous
   touches, pen proximity, pressure, eraser end, side buttons and palm contacts.
5. Repeat with rotation/scale changes and a second monitor. Confirm the correct
   output receives input; a working pen is not evidence of correct mapping.
6. For missing tablet metadata, follow libwacom's
   [new-device procedure](https://github.com/linuxwacom/libwacom/wiki/Adding-a-new-device).

### TDP and fan controls

1. Select a backend only after identifying model, firmware, driver and exposed
   interfaces. Start read-only; unsupported devices must say unavailable.
2. Record the original values, supported ranges and AC/DC state. Keep one owner
   for power control; do not let competing daemons overwrite each other.
3. Apply only model-supported settings, read them back, then observe power,
   thermals and throttling under a repeatable load.
4. Restore defaults on failure, service restart and profile exit. Test AC/DC
   transitions and resume separately; firmware may reset values.
5. Do not expose raw VRM-current, thermal-protection or unknown ACPI/SMU writes.
   HHD explicitly warns that current-limit changes can damage hardware.

PowerStation provides an AUR installation route upstream. That makes packaging
possible; it does not establish safety or support for a particular device.

### Receiving a cast

1. Use a reviewed UxPlay release. The default branch reviewed here identifies
   1.74 as experimental; do not automatically ship experimental discovery code.
2. Run as the user, not root. Require a displayed PIN or reviewed access-control
   mechanism; do not expose an unauthenticated receiver on a public network.
3. Verify discovery, permitted and denied connections, then real video/audio.
   Upstream documents `waylandsink`, `pipewiresink` and software-decode fallback;
   select only plugins available in the image.
4. Measure frame rate, audio/video sync, GPU-vs-software decoding and sustained
   CPU/power use. A GStreamer test pattern is not an AirPlay end-to-end test.
5. Test sender disconnect, network loss, receiver stop, suspend and screen lock.
   The indicator must disappear and listening ports/processes must close.

This validates AirPlay, not Chromecast, Miracast or DRM video. UxPlay documents
DRM and AirPlay2 multi-room limitations.

## Evidence required before marking hardware supported

Store in the appropriate product tests or shani-testbed, not a session scratchpad:

- device model and firmware; kernel/driver/backend/package versions;
- Shani source commit, profile, display topology, scale and input mapping;
- exact reproduction, sanitized logs/capture and measured expected outcome;
- positive case plus a negative control (unsupported device, denied permission,
  missing backend, disconnect or invalid range);
- who ran the physical test and when; known limitations;
- a regression fixture where possible, plus the physical retest result.

Use distinct labels: **upstream-documented**, **mock-tested**, **replay-tested**,
**physical-device-tested**. A green CI badge, device list or screenshot cannot
be silently promoted to the last category.
