# ShaniOS shell spike — findings (2026-10-27)

## State at close

- Stack: **niri 26.04 + Quickshell 0.3.2** (nested under weston headless, 1920x1080).
- Chronoa integration: **verified end-to-end** over real D-Bus + unix socket.
- QML config: **loads clean** (after fixing brace balance + IPC arg typing).
- AI panel: ask → thinking → tool pills → cue → approval → streamed reply → done.

## Chronoa integration (this session's work)

Real contracts read from `~/Documents/shani/shani-chronoa`:

| Contract | Methods | Status in product code |
|---|---|---|
| `org.shani.Chronoa.Mascot` | `Art`, `Status(title, detail)`, `Rect`, `Notch`, `PanelHeight`, `Pointer`, `Show(visible)`, `Scale` | ✅ implemented (`mascot_notch.py`, `mascot.py`) |
| `org.shani.Chronoa.Windows` | `Cue(text, hold)` | ✅ implemented (`automation_overlay.py`) |
| `dev.shani.chronoa.Gateways` | `Submit(gateway, text) -> reply` | ✅ implemented (`gateway.py`) — **fire-and-forget** |
| `dev.shani.chronoa.Agent` | `Turn(text) -> id`, `Approve(id, decision) -> ok`, `Event(json) signal` | ✅ **implemented** (`agent_service.py`) — turn stream with approval |

Shell-side wiring that now works:

```
Quickshell (shani-chronoa panel/cue) --unix socket (JSON lines)--> shani-chronoa-shell-bridge (D-Bus owner of
  org.shani.Chronoa.Mascot / .Windows, calls dev.shani.chronoa.Agent|Gateways)
                                   --> mock-chronoa (dev.shani.chronoa.Agent|Gateways, script-driven)
```

Bridge fixes landed this session: socket now `ThreadingUnixStreamServer`; single
`Gio.bus_get_sync` connection owns **both** names via `bus_own_name_on_connection`;
broadcasts a `hello` event on connect; shell maps `hello/state/cue/mascot/event/error`.

QML fixes landed this session:

- `shell.qml`: missing closing braces for the notification window (parse error fixed);
  `IpcHandler` methods typed (`ask(text: string)`, `action(name: string)`);
  added `approve(decision: string)` IPC → newest unanswered approval;
  added Chronoa state props, socket client, `ask`/`action` wiring, bar Chronoa pill,
  cue window, conversation panel.

Panel/pill fixes landed: removed accent-glow that spilled outside card border;
added empty-state copy for `model.count === 0`.

## Verified behaviour

- `qs -c shani ipc call shani openChronoa` → panel opens (Overlay layer).
- `qs -c shani ipc call shani ask "Tidy my desktop"` → user bubble → tool pill
  (`Scanning ~/Desktop`) → cue pill (`Chronoa: Scanning ~/Desktop`) → approval card
  → approve → tool pill (`Moving 14 files`) → streamed reply → done → bar pill back
  to ready.
- `ask "What is eating my battery?"` → two tool pills, streaming reply, cue, status
  `Thinking → Speaking`.
- Launcher (`openLauncher`) + bar shots: render clean, no QML errors since restart.

## Findings / gaps to report to the user

1. **Turn-stream API:** Chronoa now implements `dev.shani.chronoa.Agent`
   (`Turn`, `Approve`, `Event`) in `shani_chronoa.agent_service`; the shell
   bridge calls it and falls back to `Gateways.Submit` when it is absent.
2. Real `dev.shani.chronoa` **app** (for `toggle-listening`/`quick-ask`/`dictate`/
   `stop-speaking`/`show-page` actions) is not running in the container, so the mock
   owned only Agent/Gateways. The bridge's `action` path currently calls
   `org.freedesktop.Application.ActivateAction`; expects `dev.shani.chronoa` to be
   exported as an app there.
3. Mock is scripted, not model output — screenshots/flow tested with scripted turns;
   reply prose is canned.
4. The local model server (llama.cpp, 8B, 4 threads) holds ~10 GB RSS; bridge+mock ~31 MB
   each; Quickshell idle ~166 MiB RSS / 24 threads / 30 fds / **0.2 % idle CPU** over 10 s.

## Blur verification (this session)

Three niri configs, same session, same backdrop, re-checked 2026-10-28 after the
Agent/panel changes (`dev/blur-test.sh <name> <config> <blur>`):

| run | what asks for blur | result |
|---|---|---|
| `protocol` | shell, `BackgroundEffect.blurRegion` (`SHANI_BLUR=1`) | blur only under the panel; desktop untouched |
| `rule` | niri `layer-rule` on `shani-*` namespaces (`SHANI_BLUR=0`) | whole output blurred |
| `none` | nothing | sharp control |

Measured through the panel card, over a line of terminal text and a row of
coloured blocks (grayscale std-dev, so lower = flatter = blurred):

| feature behind the card | none | protocol | rule |
|---|---|---|---|
| text line | 0.0161 | 0.00041 (39× flatter) | 0.00165 |
| colour swatches | 0.0345 | 0.00038 (90× flatter) | 0.00419 |

Blur is also correctly *bounded*: comparing the sharp desktop to the left of the
card, `protocol` vs `none` is RMSE **0** (pixel-identical), while `rule` vs `none`
is 0.072 — the layer-rule run smears the terminal text and the wallpaper wordmark
that the panel never covers.

Why: Quickshell's layer surface spans the whole output, and a niri `layer-rule`
blurs a whole surface — it cannot see the QML-shaped region. `ext-background-effect-v1`
carries an explicit per-surface region, so it blurs exactly the card/bar/launcher.

Deliverable state: the protocol path is the only supported one (`SHANI_BLUR=1`,
`dev/niri/protocol.kdl`). `dev/niri/rule.kdl` stays as a demonstration of the difference,
not as a fallback — do not ship it.

## Next moves

- Wire the app's own window to the Agent sink so a turn started in the panel and
  a turn started in the window look the same in both places.
- Real-app activation path in the container to test `dev.shani.chronoa` actions.
- Sharper final wallpaper (current one is mostly gradient+grid; SHANI wordmark ended up
  under the demo terminal).
- Final hero screenshot with panel + bar + cue in one frame.

## 2026-10-28 — the Agent contract is real

`dev.shani.chronoa.Agent` is no longer a shape the mock happens to speak. It is
exported by `shani_chronoa.agent_service.AgentService` from the app, and the
shell's bridge is its client.

What the real turn stream settles:

- **One resolver per turn, not one per process.** The first wiring installed a
  global `set_agent_resolver`, which would have sent the *window's* questions to
  the shell as well. The resolver is now a `contextvars.ContextVar` bound by
  `Turn` while it schedules the coroutine; the assistant already copies the
  context into the executor that runs tools, so a question asked from a tool
  thread finds its turn and no other.
- **The sink is an `EventSink`.** `Assistant.handle` calls `sink.fire(...)`
  whether or not the object has it; the old `_AgentSink` raised `AttributeError`
  on the first tool call of every shell turn.
- **`Approve` returns whether a question was waiting.** The introspection, the
  shell's mirror and the mock all carry the boolean now; a card answered after
  its wait expired says so instead of looking like it worked.
- **The shell gets the option labels.** `approval.options` is the list `ask()`
  was given, and the panel draws one button per option and sends the chosen
  *label* back. The old card sent `once`/`always`/`deny`, which
  `permissions.parse_reply` does not match - "Allow for this session" would have
  been read as neither.
- **Two bus bugs fixed by actually running it.** `emit_signal` needs the
  destination first (`None, PATH, IFACE, …`); without it every event raised
  `TypeError: Must be string, not Variant` inside a GLib idle callback, which is
  to say the shell heard nothing. And the `Turn` dispatch already ran off the
  main loop, so the approval gate itself was fine.
- **Approval expiry is drawn.** A timeout closes the card (`approval_closed`)
  rather than leaving a button that answers nothing.

Evidence:

- `tests/test_the_agent_turn_stream.py` — 5 tests: routing from a tool thread,
  the window's own questions still going to the presenter, expiry, per-turn
  isolation, and the `EventSink.fire`/pill mapping.
- `tools/check_agent_bus.py` (shani-chronoa) — a real session bus:
  `Turn -> tool -> approval -> Approve(True) -> tool_done -> reply -> done`.
- `tools/run_agent_host.py --serve` + this shell in the container: the panel
  drew the real service's pill, a 3-option approval, and `✓ Allow for this
  session`, with the tool pill gaining its ✓ from `tool_done`.

Smaller fixes landed with it: the bar's `stats.sh` now exists (it was referenced
but missing, so load/mem read 0), the socket path follows `XDG_RUNTIME_DIR`
instead of a hard-coded `/run/user/0`, and the demo terminal no longer opens with
a foot config error.

## 2026-10-28 — review pass: only our turns, and the transcript tells the truth

Three things the end-to-end runs exposed, all fixed and re-measured in the
container against the real `AgentService`:

- **A bus-wide turn stream is not a private one.** Any client can call
  `Turn`, and every client sees every `Event`. A turn started outside the bridge
  (`gdbus call … Agent.Turn`) used to draw its pill and its approval card in
  the panel. `bridge/turn_filter.py` now forwards only the turns this bridge
  opened. Events that race the `Turn` reply are *held*, not dropped - the
  service queues them onto the GLib loop, so the first `tool` can arrive before
  the id it belongs to - and flushed when the reply lands. Held foreign turns
  are bounded (8 turns, 64 events each) so a stranger's turn cannot grow the
  bridge. Verified both ways: a `gdbus` turn leaves the panel at "Ask for a
  job."; a bridge turn paints pill, card and reply as before.
- **`approve "Allow for this session"` now means that option.** `optionFor()`
  read the IPC argument as a code (`deny`/`always`) and fell through to
  `options[0]`, so asking for the session option recorded "✓ Allow this once"
  - and sent that label to Chronoa. It matches an exact label first now. The
  decision a card shows is the decision that was sent.
- **The newest reply is visible.** The transcript was a `ListView`; its last
  delegate was laid out (correct `y`, correct height) but never painted until
  another row arrived, and `positionViewAtEnd()` stopped one row short. The
  model was never wrong - dumping it showed the reply row present. It is now a
  `Column` inside a `Flickable`, which has no recycling and no delegate pass:
  `contentY = contentHeight - height`, and the empty state hides the list so
  "Ask for a job." is centred instead of sharing the space with an empty view.

Tests: `tests/test_turn_filter.py` (12) with 8 mutations, all caught
(`foreign-forwarded`, `take-does-not-drain`, no cap on unclaimed turns or on
events per turn, no LRU bump, no cap on known ids, turn-less events withheld).
`python3 -m pytest tests -q`.

Still open: the GTK window's own turns do not go through `Agent`, so the two
surfaces do not look alike yet (next move 1).

## The AI desktop rebuild (2026-10-28)

Restructured into Common/Services/Modules (after Dux Shell's layout, see the
research in this session), then every feature driven for real in the dev
container. Results: `dev/shell-test.sh` 31+ checks, greeter 5/5, polkit 6/6 in a
real logind session, bridge pytest 14 (turn filter + logind).

Bugs that only execution found — each would have shipped from reading alone:

| Bug | How it showed | Fix |
|---|---|---|
| `onAccent` as a property name | parsed as a signal handler for `accent`: whole config failed to load | renamed `accentInk` |
| service `Network` | Quickshell.Networking's own `Network` type shadowed it in the sidebar: "`scan` is not a function" | renamed `Net` |
| service `Rotation` | QtQuick's `Rotation` (transform) type shadowed it: tiles read `undefined` | renamed `AutoRotate`; all names now checked against the 189 exported types |
| module `Chronoa` | same name as the `Chronoa` service singleton | `ChronoaSurface` |
| launcher one query behind | `launcher` flipped before `launcherQuery` was set; the panel read the old query on open | set the query first |
| idle never fired | **IdleMonitor ignores a `timeout` change after creation** (measured: created at 300 s, set to 2 s, never idle); settings load after startup, so user timings and the AC/battery switch did nothing | each stage is a Loader rebuilt on timeout/switch change |
| password lost after a wrong one | PAM's failure delay kept the field disabled; what was typed then vanished | field stays live; an answer typed while busy is queued |
| `lock.locked = false` on unlock | broke the `locked: Lock.locked` binding: the next lock would never engage | unlock only through the service; a watchdog re-binds if the lock is lost |
| `stats.sh` on Arch | gawk rejects `load` as a variable (the spike's awk accepted it) | `/proc` read by FileView instead; script deleted |
| test PAM dir | `auth include login` resolves against the PAM *directory*; a copy outside /etc/pam.d failed every attempt, right or wrong — and "wrong password refused" passed for that reason | the test installs the real file in /etc/pam.d; later checks first assert the screen *is* unlocked |
| Chronoa `Show("true")` | the notch sent strings to a `b` argument; refused, swallowed: the strip never came back after a Shell restart | booleans (shani-chronoa) |
| Chronoa never fed the shell | on niri (layer-shell available) `mascot.create()` always chose its own floating window; the bridge's `Art` answered False | `Host()` on the Mascot interface; a host shell gets the strip surface (shani-chronoa, tested) |

Not verifiable nested: wf-recorder gets a 0×0 frame from a nested niri even
with `-g` and `--no-dmabuf` (grim captures fine) — real recording, night light
(gamma-control is only offered on real outputs) and auto-rotate go to
shani-testbed.

### Second round (same day): what else a desktop needs

| Bug | How it showed | Fix |
|---|---|---|
| PipeWire `properties` empty | an untracked node's `properties` (media.class …) read `undefined`: the mixer, "mic in use" and the input list matched nothing | classify by `type` flags (playback = Audio\|Stream\|Sink = 21, capture = 13); track video sources before reading `device.api` |
| service `InputMethod` | another type-name clash: the sidebar read `undefined` | renamed `Ime`; every service/module/widget name now checked against all 270 exported QML types |
| emoji never loaded | `FileView.reload()` on a view whose path was never set loads nothing | set the path on first use |
| squeekboard: no Devanagari | its only Indic layout is Malayalam; stevia has Hindi Bolnagri, no Marathi; both take the input-method slot fcitx5 needs | the shell's own keyboard over the virtual-keyboard protocol (wtype): any script, no slot conflict |
| OSK language after a list change | the keyboard kept its index, so a new list silently put it on a different language; the test's missed switch did not fail loudly | keep the language if still listed, else the first; a missed switch is now a FAIL |

Screen-keyboard layouts come from libxkbcommon itself (`bridge/osk-layout.py`):
598 layouts and variants, 45 Indian — a superset of stevia 0.58's 60 (whose only
Indic layouts are Hindi Bolnagri and Malayalam). Gboard's transliteration
layouts (type Latin, get Devanagari) are an input-method feature: fcitx5 + m17n.

### Third round: borrowed concepts, voice typing

| Bug | How it showed | Fix |
|---|---|---|
| shell hang | a MouseArea inside a Row, sized to the Row, fed the Row's width back into itself: every IPC call blocked | a TapHandler (handlers take no space); `st()` now times out so a hung shell fails the next check |
| test, not product | the window-menu check's inline Python misread niri's state; the window had moved (the Lens shot showed it on workspace 3) | a plain `widx` helper; Lens clears its workspace first |
| test, not product | absolute notification counts broke when the battery saver (reading the host laptop's battery through UPower) posted its own | deltas |

Voice typing, end to end in the container: espeak-ng says "good morning everyone"
into the null speakers, the mic (their monitor) records it, whisper.cpp's tiny
model transcribes "Good morning everyone.", and it is typed into the launcher.

### Fourth round: beauty, borrowed features, accessibility

| Bug | How it showed | Fix |
|---|---|---|
| adaptive brightness (written alongside this work) | `Process` declared inside a JS function: the shell did not load; also an unreachable fallback, LED brightness read as lux, and every automatic change taken as a manual override (it stopped after one step); the OSD popped on each 5 s sensor read | moved the reader out; IIO illuminance only; `Brightness.applyAuto` marks automatic changes; override lapses after 30 s; OSD only on real changes |
| settings write race | a quick on-then-off came back on: the file watcher reloaded the shell's own write over a newer change | first a flag (swallowed the next hand edit — FileView does not report its own writes), then a 300 ms window (outlived under load); finally by content: a change is applied only when the file differs from what was last written |
| removed keys kept | JsonAdapter leaves a key missing from the file at its current value: a settings.json reset to `{}` changed nothing (a stuck Work schedule, an orange wallpaper in later tests) | outside edits apply defaults + file |
| tabular figures script | inserted `font.features` after the first line of a two-line binding | fixed by hand; every insertion checked |
| `Timer` service name | would shadow QtQuick's Timer | `FocusTimer` |

Accessibility, checked the way Orca sees it: dev/a11y-tree.py walks the real
AT-SPI tree; the sidebar's tile reads "check box · Do Not Disturb · checked".

### Fifth round: captions, read aloud, magnifier, call recording, smart copy, smart touch

| Bug | How it showed | Fix |
|---|---|---|
| ScreencopyView in nested niri | the magnifier's frozen frame killed the shell at load: `invalid version for zwp_linux_dmabuf_v1.get_default_feedback (3, need at least 4)` | the frame is taken by grim (wlr-screencopy), with the loupe hidden while it is taken |
| whisper on silence | captions of playback came out "you you you": every silent 4 s chunk is heard as "you", pushing the real line out | `dictate.py` drops recordings under about -50 dBFS before the engine sees them (voice typing gains it too) |
| `Quickshell.clipboardText` | a copy made in another app never reached the smart suggestion: it only changes while a shell window has focus | `wl-paste --watch` (wlr-data-control), one line per copy |
| `parent` inside `ClippingRectangle` | the Shelf thumbnails never loaded (`Cannot read property 'path' of undefined`), and the launcher's image preview loaded while hidden: a child's `parent` is the clipping content item, not the rectangle | refer to the rectangle by id |
| snooze test counted all notifications | a screenshot offer closing meanwhile made the count one short | the test looks for the snoozed notification by its summary |
| no Bluetooth agent | Quickshell pairs but registers no agent: a phone or keyboard that shows a code could not pair under niri | `bridge/bt-agent.py`, the default agent, asks through a pairing dialog; tested against a fake BlueZ |
| `xdg-mime` 1.2.1 | `default` exits 0 without writing when `~/.config` is missing; `query default` reads `mimeapps.list` and then answers the system default anyway | default apps through `gio mime` (what GTK apps ask) |
| niri `include` and flags | an included file cannot switch off a flag (`tap false` is a parse error) | the base config leaves `tap`, `dwt`, `natural-scroll` and the layout to the shell's `~/.config/niri/shani-input.kdl` |
| settings split into categories | declarations moved into the category blocks while the code still read them as `page.…`: `nameOf is not a function` | declarations hoisted back to the page root |
| `Speak.speak()` | its own detached `pkill espeak-ng` could land after the new utterance started and cut it off | the cancel runs first, in the same command |

### First-boot setup (shani-setup)

ShaniOS installs no account and a factory reset removes them all; on Plasma and
GNOME their own wizards make the first one, and the niri desktop had none — it
would have booted to a login screen nobody could use. The greeter niri now runs
`qs -c shani-setup` while no regular account exists (no "done" flag to lose, so
it re-arms after a reset). Its one privileged step is `bridge/first-account.py`
through pkexec; checked against the real polkitd (`dev/setup-polkit-test.sh`):
only `greeter`, only that program, and the program refuses once an account
exists. `dev/setup-test.sh` walks the wizard end to end and signs in through
the fake greetd.

| Bug | How it showed | Fix |
|---|---|---|
| `pgrep -f 'qs -c shani-setup'` | matched the greeter niri's own `sh -c "… qs -c shani-setup …"` line: "setup still running" on a set-up machine | anchored: `^qs -c …` |
| `C.utf8` offered as a language | the filter dropped `C.UTF-8` only | C and POSIX in any spelling |
| a clock beside the chosen zone | showed this machine's current zone's time, not the chosen one's | removed |
| hostname in a container | hostnamed: EBUSY (docker bind-mounts /etc/hostname) | reported as a warning, the account still made; the check SKIPs in containers |

### Users, power keys, sound effects

| Bug | How it showed | Fix |
|---|---|---|
| two-word launcher searches | "default browser", "time zone", "add user" fell through to "Ask Chronoa": an action matched only when one of its words began with the whole query | every word typed must begin some word of the title or keywords, any order |
| smart suggestion came back | a later suggestion was replaced by the earlier copy's: wl-clip-persist takes the clipboard over after each copy, so wl-paste --watch announces the same text twice | the same text again is not a new copy |
| autologin check in a container | `systemctl cat greetd.service` had nothing: greetd was not in the dev image | greetd installed; the test reads what systemd will run (`systemctl show -p ExecStart`) |
| refused display change asked to be kept | turning off the last screen was refused, yet "Keep these display settings?" counted down: the old settings were recorded before the change was checked | record only once the change is known to be one |
| keyring locked after every login | greetd's PAM stack has no pam_gnome_keyring | `/etc/pam.d/shani-greetd` (greetd's stack + the keyring), named by `[general] service` |
| no play/pause/next keys | niri's config bound only volume and brightness | XF86Audio{Play,Pause,Next,Prev,Stop} through the shell to the playing MPRIS player |
| first copy after start swallowed | "skip the first clipboard event" assumed one is announced at start; an empty clipboard announces nothing | by time: only what arrives in the first 1.5 s |
| own shortcut press in a test | `wtype` keys never reach niri's binds (virtual keyboards go to the client) | the test checks the bind niri loads; the press is a real-keyboard check |
| stale test containers | `timeout -s KILL docker run` kills the client, not the container: an old run kept writing into the same work directory | named containers, removed before and after |
| loudness levelling ports | PipeWire's ebur128 plugin documents no port names | read from the plugin and proven by loading the graph: `Shortterm LUFS` → `lufs2gain:LUFS`, `Gain` → a mixer's `Gain 1` |

### Half-done features, found by auditing what each one should let you do next

| Bug | How it showed | Fix |
|---|---|---|
| recording sound unreachable | the recorder had `withAudio`, nothing set it; whole screen only | Screen record detail: focused screen or a part (slurp), no sound / computer / microphone |
| a stopped region selection left slurp running | stopping during the selection killed the wrapper shell only; slurp kept the keyboard over the whole screen, and the next overlay's Escape went to it (the magnifier test failed). A trap did not help either: the script inherits SIGINT as ignored, and an ignored-on-entry signal cannot be trapped | the script reports slurp's pid and stop kills exactly it; the Island says "Choose an area" until recording really starts |
| "clear clipboard history" left the secret in it | the text was still on the clipboard; wl-clip-persist offers it again and cliphist stores it straight back | clearing also empties the clipboard and the primary selection |
| noise suppression off: default source not restored | "Cannot change default source to a node that is not a source" — the previous default can be a monitor | restored by name (`pactl set-default-source`) |
| "channelVolumes and channelMap are not the same size" | the mono RNNoise node reports two volumes for one channel | run it stereo, as PipeWire's own example does; the mic slider acts on the real microphone |
| Update button did nothing | it opened Cassini, which the niri desktop may not install (Cassini is shipped on the niri image today; the fallback covers hosts without it) | Cassini where present, else `pkexec shani-deploy` in a terminal |
| initials instead of pictures on the login screen | the greeter reads AccountsService, which the desktop did not install | `accountsservice` in shani-desktop-niri |
| fonts ignored | the Chronoa panel and the greeter hard-coded Noto Sans / DejaVu (23 places) | Theme.font / Theme.mono |
| proxy applied by the Settings page | it worked only because the page happens to be built at startup | a Proxy service |
| right-click on a dock icon toggled its pin, silently | no way to reorder, open a new window or close all | a menu: new window, pin/unpin, move left/right, close windows |
| no single clipboard delete; no hibernate; wallpaper only from two folders; no sending files over Bluetooth | — | Shift+Delete in clipboard mode; Hibernate where logind can; any picture by path; Shelf → Bluetooth → a paired device |

### Defaults and the last settings

| Bug | How it showed | Fix |
|---|---|---|
| the default wallpaper aged | "niri 26.04 · quickshell 0.3.2 · chronoa" was printed on it | a generated pair (assets/make-wallpapers.py), no text; JPEG, 0.75 MB at 4K where PNG with its anti-banding noise is 9 MB |
| a wallpaper picked for both styles did not show | the new per-style defaults won over it | picking one for both clears the per-style ones (Settings, slideshow, the tests too) |
| first login in Adwaita and GNOME's defaults | the shell writes the look only once running, after it has started with the old icon theme | the same values as a GSettings override in shani-desktop-niri |
| clearing clipboard history, again | `wl-copy --clear` leaves the clipboard empty, which wl-clip-persist answers by restoring the last contents | an empty text replaces it, then the history is wiped |
| foot's colours rejected | foot 1.28 renamed `[colors]` to `[colors-dark]` | checked with `foot --check-config` |
| idle lock during the test run | the suite outlasts the 5-minute default and IPC is not input: the screen locked and later keys went to it | the test session starts, and every `settings` write keeps, idle off |
| volume keys ignored the shell | niri spawned `wpctl … -l 1.0` directly: no step choice, no over-amplification | the keys call the shell |

## 2026-10-29 — OSDs, the ambient light sensor, an audited feature gap and closing it

### The OSD set and adaptive brightness

| What was asked | What it got |
|---|---|
| mic volume OSD | `onMicVolumeChanged`: the mic level as a slider pill, like the speaker's; the interactive slider was already in the control centre (`SidebarSliders`), with a live peak meter |
| a full OSD set | volume, speaker mute, mic mute, mic volume, brightness, adaptive on/off, sensor found, caps/num lock, keyboard layout, power profile, night light, DND, caffeine, focus mode, display scale, flashlight, network online, battery saver |
| ambient sensor brightness | new `Services/AmbientLight.qml`: IIO illuminance sysfs only (`in_illuminance_input|_raw`, `/sys/class/ambient_light/*`); exponential smoothing (α 0.2), a dead-band of 0.05 in level and a sticky target so a stable room does not repost the OSD every 5 s; manual override holds the sensor off 30 s (the read timer stops while the override is up); no sensor → the time-of-day curve; `SHANI_LUX_FILE` gives the suite a sensor at /tmp/fake-lux |
| DDC/CI monitors | `Brightness.applyAuto()` drives `brightnessctl` for the panel and `ddcutil` for external monitors, and `Brightness.automatic` keeps the change from arming an override |

The one trap worth writing down: `/sys/class/leds/*` "brightness" is what a light
is *emitting*, not what the room looks like — a first draft of the sensor probe
listed LED class devices, which would have read (and then dimmed by) the torch
LED. IIO illuminance only. And "sensor on" one shot per boot beats a settings
toggle OSD: the pill says "Ambient light sensor found", after which the person
knows to look in Settings.

Verified in the clean container run: `ambient-follows-sensor` (300 lx → 74 %),
`ambient-dims-to-floor` (60 lx → the 0.12 readability floor), `ambient-off-stops`
all PASS. The three stale FAILs from an earlier (mid-edit, corrupted) run —
`accent-from-wallpaper`, `clipboard-image-entry`, `notification-snooze-returns` —
pass clean, which shows they were run-corruption, not bugs: no edits while a
suite is in flight, bash sources scripts lazily.

### The audit: gap analysis against GNOME 48 / Plasma 6 / macOS Sequoia / Windows 11

Verified already present (the audit's four false gaps, found in code):
`batteryLimit` (sysfs `charge_control_end_threshold` via shani-admin), launcher
file search by name *and* content (localsearch/rg/grep), Quick Look file preview
in the launcher, drawing-tablet map-to-output + left-handed.

Closed this round — the two real gaps that were closable:

| Gap | Implementation |
|---|---|
| per-app window rules (Plasma's Window Rules, macOS's per-app tiling) | `Services/WindowRules.qml` writes `~/.config/niri/shani-windows.kdl`, included by the niri config (the `InputConfig` pattern): floating, named workspace, opening width; Settings › Windows rows; can't be missed: `niri msg windows` shows the app ids to type |
| world clocks (macOS, KDE) | `Services/WorldClock.qml`: zoneinfo zones via `TZ=z date` (DST by construction), rows under the calendar, 30 s refresh only while cities are picked |

niri facts the implementation rests on (probed for real, each in a nested session):
`open-on-workspace` takes a *name* (numbers are a KDL type error; default
workspaces are unnamed); rules in an included file are parsed by `niri
validate` but the first config load drops them — the first reload applies them,
and the shell writes the include after niri starts, exactly as the input file
does. `niri msg -j windows` reports `is_floating`, which is how the suite
verifies a rule for real.

### The gaps that are not ours to close (blocked upstream, verified by probe)

| Feature | Why blocked |
|---|---|
| colour filters (deuteranopia etc.), HDR | niri 26.04 has no `custom-shader`/`color-transform`/`hdr` output node — every candidate validated as an unexpected node |
| per-output gamma | niri 26.04 has no `gamma` output node; gammastep is now an optdepend and the `Gamma` service applies it (and pauses NightLight while active) |
| sticky/slow/bounce keys | needs compositor-level key interception (mutter does it in-compositor); nothing niri exposes |
| remote assistance (GNOME Remote Login / Quick Assist) | FreeRDP shadow server is now an optdepend and the `RemoteAssist` service starts/stops it and prints a connect address; a full compositor capture path is still niri's to provide |

### Suite (clean container run this pass)

Third clean run pending at write time: first run 225 PASS / 4 FAIL; second 226
PASS / 6 FAIL (two self-inflicted by the integer `open-on-workspace`, one
counted twice: `dynamic-lock` flaked FAIL once, PASS the next — a timing race
in a 6 s budget with a 1.5 s grace; owes the real testbed a quiet verdict, as
do `pinned-window-follows`, `unpinned-window-stays`, `hot-corners-off-in-fullscreen`,
which fail identically in the container in every run and are testbed-only).

## 2026-10-29 — second gap pass: audio, accessibility, notifications, screenshots

### More gaps closed (verified feasible, not blocked upstream)

| Gap | Implementation |
|---|---|
| per-app audio routing (Plasma's "Application" tab in Audio, Windows' app volume mixer) | `Audio.streamSink()` reads the Active link in `Pipewire.links`; `Audio.moveStream()` runs `pactl move-sink-input` (Quickshell exposes read-only links) matched by the stream's `node.name` |
| left/right balance | `Audio.setBalance()` writes per-channel volumes through `pactl set-sink-volume @DEFAULT_SINK@` (positional channels); centred writes nothing, so the master slider stays master; re-applied on default-sink change |
| reduce transparency (GNOME, macOS) | `Settings.data.reduceTransparency` → `Glass.qml` paints opaque `Theme.bg` |
| disk-usage analyser (baobab / DaisyDisk) | `Drives.scanStorage()` runs `du -x -d2` on `$HOME`, top 9; `SidebarDrives` "Storage" section with sizes |
| fast user switch (GNOME, Windows) | lock-screen "Switch user" button → `Lock.switchUser()` → `shani-admin.py switch-greeter` → `loginctl switch-to-greeter`; tested via `SHANI_ADMIN_TOOL=/work/dev/fake-admin.sh` |
| location services (GNOME, macOS) | `Services/Location.qml` queries GeoClue2 (where-am-i / D-Bus client) and fills `weatherLat`/`weatherLon`; `Settings.data.useLocation` (off by default); real-hardware only |
| OCR on screenshots (GNOME Lens, macOS Live Text) | screenshot notification gains "Copy text": `tesseract … \| wl-copy` |
| reduce motion (accessibility) | `Settings.data.reduceMotion` forces niri's `animations { off }` (InputConfig) |
| quiet hours / DND schedule (Windows focus assist, macOS DND) | `Notifs` timer sets `doNotDisturb` from `dndSchedule`/`dndFrom`/`dndTo`; Settings › Notifications row + from/to fields |

### Still blocked (unchanged, verified by probe)

colour filters/HDR/gamma, sticky/slow/bounce keys, remote assistance — see the previous round.

### Suite

Run in progress at write time; persistent testbed-only FAILs remain
`pinned-window-follows`, `unpinned-window-stays`, `hot-corners-off-in-fullscreen`,
and `accent-from-wallpaper` (flaky, passed in two of three runs).

### Corrections (later the same night)

Three of the rows above were withdrawn after review, and one fixed:
- **remote assistance**: FreeRDP's shadow server cannot capture niri (no
  RemoteDesktop interface in 26.04, niri #390), and it listened on 3389 with no
  authentication set. Removed; Sunshine is the remote desktop (Settings > Sharing).
- **fast user switch**: `loginctl switch-to-greeter` is not a loginctl command,
  greetd runs one session, and it ran as root for nothing. Its test only saw a
  stand-in being called. Removed, with the session-wide `SHANI_ADMIN_TOOL`
  stand-in that silently replaced every Users/Power action in the suite.
- **per-output gamma**: gammastep 2.0.11 has no `-S`/`-s`, and it fought
  wlsunset over the gamma ramp. Removed.
- **location**: no demo agent any more (it approved every app's request while
  it ran), no `/work` path in the service, the helper is packaged, and the
  D-Bus path (no DesktopId, no main loop: it could never answer) is gone -
  GeoClue's where-am-i only.
- Also fixed: the per-app routing script (a Python quoting error - it never
  ran; now `pactl move-sink-input <object.serial>`), balance setting the volume
  to 100 % and never re-centring, a test clean-up that unloaded every null sink
  (9 audio tests failed after it), and `PASS || PASS` checks.

### 2026-11-03 — render harness rewrite + all-surface render; broken-code fixes

**The shell would not start.** Uncommitted `Services/ScreenSaver.qml` had its
`startCover`/`stopCover` pasted *after* the `Singleton { … }` block, referencing
an undefined `settings` — a hard QML syntax error. Every Quickshell instance
died at load; `state` answered nothing and every pre-existing render was of an
unusable shell. The functions now live inside the Singleton with
`Settings.data.*` references.

**`qs.Services.Color` was shadowed by `QtQuick.Color` (6.12 value type)** in
every file importing both (i.e. all of them): `Color.pick()` / `.lastPicked`
resolved to undefined, so the Sidebar's colour-picker tile was dead and its
Connections handler was the one thing in the log warning about it. Fixed by
qualifying the singleton (`import qs.Services as Services`) in SidebarTiles.qml.
All 79 singleton names were checked against every Qt/Quickshell export; the
only other match needs `import QtCore` (never imported). Logged as a rule: a
singleton may never share a name with a QtQuick type.

**Render harness (`dev/render.sh`) rewritten as the canonical renderer.**
Modes: `shell` (default) · `greeter` · `setup` · `all` (setup → greeter →
shell, with full compositor teardown between) · `--one` for a single surface.
`render-all.sh` / `render-verify.sh` now exec it; `render-one.sh` unchanged.
Output: `docs/renders/<mode>/<nn-name>.png` (git-ignored).

Wrong-invocation bugs in the old scripts, all fixed:
- `controlCenter <Settings-page-name>` set a `Ui.expanded` no view reads —
  every CC "section" shot was the untouched sidebar. Now only the real section
  ids are used (wifi bluetooth vpn audio power access display timer focus
  record phone); Settings pages render via `settingsCategory` with the full
  list, **adding printers and account** (were missing).
- `flashAlert` and `scratchpadToggle` are not IPC commands; the calls failed
  silently and grim photographed the unchanged screen. Flash alerts now set
  `flashAlerts` + send a notification; scratchpads are niri windows, not a
  shell surface, and are not rendered.
- **The lock screen is a session lock: `closeAll` never unlocked it.** Every
  capture after the old "lock-screen" shot was a locked screen. The script
  sets root:shani-test (as the suite does) and types it via wtype, and aborts
  loudly if the screen stays locked instead of silently shooting a lock.
- grim/notify/clipboard now have the state they need (wl-copy before the
  launcher's c-mode; /tmp/test-share.txt touched before share).
- **Captures that photograph an already-open surface bypass the close-first
  step** (new `capture_current`) — the old flow closed the surface it was
  about to photograph (ring-at-point, notifications, OSD, modals…).
- Settings applied mid-run go through a JSON merge helper (file is watched).

**New surfaces covered that the old scripts never rendered:** greeter
(login · auth-failed · OTP second prompt, via fake-greetd) and the first-login
Setup wizard (welcome · Marathi · Deutsch · keyboard · network · time ·
account · password-mismatch, walked over IPC like a person; never completed,
no account is created), plus dock context menu, layout switcher, ring at a
point and the Power sub-ring, mic-mute/volume/brightness-down OSDs,
notification inline actions, SMS notification and the SIM call flow (island +
notification, via the fake modem), SMS composer, display-confirm (winit
scale 1.5 → keep), Bluetooth pairing dialogs (confirm + shown passkey, via the
fake agent), desktop widgets + island now-playing (fake MPRIS), assistive
touch, flash alerts, overview search, lock refusal + unlock,
launcher-clipboard. Output 74 shots shell + 3 greeter + 8 setup (as of this
run; fails are re-rendered, not shipped).

**QML defects fixed (all log-verified):** `target: parent` in two
SequentialAnimations (unused/broken breath animations; now targeted at ids);
`mascot.jump` (id is not a member — happy-jump never animated; now `jump`);
anchors on a layout-managed empty-state Column (now a ColumnLayout, centred
via `Layout.alignment`); `anchors.centerIn: QPointF` on the press ripple in
Button/IconButton (invalid assignment; ripple now positioned by binding and
actually grows on press); `Accessible.labelledBy: null` on every TextField;
`quietWhileFullscreen` assigned `undefined` to a bool before load (GameMode).

**Known-not-fixed / deliberate:** the niri session must come up for renders to
see anything; headless captures show the resting UI for hardware-backed
panels (wifi/bluetooth/vpn/phone details, no adapter in a container). Polkit
dialog is not renderable nested (needs a real logind session; covered by
dev/polkit-run.sh). Recording in a nested niri gets a 0×0 frame — the render
captures the slurp region-select stage instead, which is what a person sees.
`configTest`/screenshots of glossy surfaces vary by GPU (ZINK unusable
headless; software Mesa is used).

### 2026-11-03 (later) — the default look: Saturn + amber brand, by default

**Brand is amber, not teal.** The shell's shipped defaults now are the Saturn
brand ("Shani's raven beneath Saturn, by day and by night", CC-BY-SA-4.0,
KDE Plasma wallpaper package) on the dark desktop, and its day look on light —
re-encoded as quality-88 JPEGs into `assets/shani-dark.jpg` (images_dark) /
`assets/shani-light.jpg` (images), replacing the generated teal aurora pair
(`assets/make-wallpapers.py` is now the re-encode recipe).

**Accent is the brand amber everywhere by default** — no more
"accent from wallpaper" roulette: `accentFromWallpaper` now defaults to
**false**, `accentName` defaults to **orange**, whose table entry is tuned to
the Saturn art's metadata accent (`#bc3e18` on light, `#ff7f50` on dark — the
same hexes as the Plasma look's `X-KDE-PlasmaImageWallpaper-AccentColor`).
`Theme.brand` is `#ff7f50`; the niri focus ring, slurp border (Lens, Region
select), the greeter/lock wordmark, GTK apps' `accent-color` and the
shell-test defaults follow. teal/blue/… stay selectable.

**What this fixes by construction:** the old default ran the wallpaper
quantizer over the teal-dark wall; on this artwork it answered `#889fd2`
(washed slate), the shell read desaturated end to end, and the screenshots
derived from it looked half-finished. The brand answer was already in the
Plasma package's metadata — the shell now ships it.

**Render-harness lesson, measured:** editing the QML *while a render is in
flight* restarts the shell each time (live-reload works — it is how the
ScreenSaver/Color/Island fixes were picked up mid-run), and the storm of
reloads starved grim until shots stopped appearing. A render is only valid on
a quiet tree: apply edits first, render once. The PNGs are written outside
the config tree (`docs/renders/`), which is not watched, so screenshots never
trigger reloads themselves.

**Foot windows no longer cover the wallpaper:** they are spawned just before
the dock/switcher/window-menu shots, not at the top of the run — the desktop
and desktop-widgets captures now show the artwork.

**Half-themed captures after a theme switch are gone:** after `setting
darkMode …` the renderer polls `state.dark` (up to 10 s) before shooting.

### 2026-11-03 (even later) — the wallpaper that never came back, and a render that proved it

**`Wallpaper.qml` cross-fade could never switch to a previously shown file.**
`swap()` assigned the wanted file to the hidden image; when that image already
held the same URL (wallpaper toggled back), the assignment was a no-op, the
Image's `status` stayed `Ready`, `onStatusChanged` never fired, and the old
(light) picture stayed up forever while `state.wallpaperNow` reported the dark
file. Reproduced exactly in the render (light→dark toggle left the day art on
screen with the dark theme's chrome). Fixed: when the target image already
holds the wanted file, clear `source` first and re-set it on `Qt.callLater`,
so `Ready` fires every time and the fade always completes.

**Render-trap, measured:** capturing right after a theme switch shot a
half-faded desktop — the wallpaper cross-fade is `Theme.anim*4`, and the shot
raced it. The renderer now polls `state.dark` and then waits for the fade
(2.5 s) before shooting. Also: foot windows (the two demo terminals) are
spawned only for the dock/switcher/window-menu shots, so the desktop and
widget captures actually show the wallpaper.

**Live-reload economics:** quickshell reloads the whole config on any change
to the tree; the previous "stuck at shot 38, niri+qs at ~150% CPU" was not a
shell defect — it was this session's edits landing mid-run, one full reload
each. Renders now always run on a quiet tree (all edits applied first).

### 2026-11-03 (wallpaper set) — ShaniOS's own art replaces the Saturn walls

**The shipped walls are now ShaniOS's own artwork** (assets/masters/*.png —
raven beneath a ringed planet, one composition in three palettes, supplied
2026-11; upscaled 1672x941 -> 3840x2160 with Lanczos and re-encoded q88 by
`assets/make-wallpapers.py`; masters kept in-repo so the JPEGs are derivable):

    day.png   -> shani-light.jpg  (light theme — blue sky)
    dusk.png  -> shani-dark.jpg   (dark theme, the default — amber dusk)
    night.png -> shani-night.jpg  (picker wall — deep indigo, Milky Way)

The Qt shell is light/dark only, so the third palette cannot be a third
"style": the amber dusk became the **dark default** and the night art ships as
a picker wall. That is deliberate — the default dark desktop is the wallpaper
that carries the brand (the two earlier attempts, night-as-dark and
twilight-as-picker-only, both rendered a blue desktop on a product whose
accent is amber).

**Accent:** taken from the wall, honestly — `picked` samples the most saturated
candidate, skips the near-greys that are just sky and rock, and pushes the
winner to a lightness that reads on the current palette. Measured on the
shipped walls: dusk `#f68f46`, day `#0966b9`, night `#4e87ee`. That is why the
dusk became the dark default: its derived accent is 9° from the brand, so the
shipped dark look is amber by construction, while the light wall's blue is the
wall's own blue (a cold wall really does cool the desktop — the feature is not
a no-op on it). `accentFromWallpaper` defaults to on for that reason; picking
one of the nine preset swatches pins that accent and switches it off.
`/usr/share/backgrounds/shani/` carries all three (dev session copies all,
PKGBUILD installs all three).

### 2026-11-03 (render pass) — three renderer bugs that were not shell bugs

**`notify-send -A` blocks.** A notification with actions waits for a chosen
action, so the renderer's `notify-send -A …` never returned and the whole batch
died at shot 39. Notifications are now sent backgrounded and killed after the
capture; 39–44 (actions, critical, DND, SMS, call) render again.

**`closeAll` is not "resting desktop".** It closes the panels `Ui` owns, but
the ruler banner, the Lens, live captions, the QR/share cards, the tour, the
phone dialog and old notification pop-ups all live in their services — so a
later Settings capture carried four overlays from earlier shots. New IPC
`dismissAll()` closes those too, and the renderer's `close_all` uses it.

**Throwaway windows outlived their shots.** The two demo `foot` windows opened
for the dock menu and switcher were never closed, so every later capture sat
on two black terminals. They now run real shell output (`shani-deploy
--status`, `systemctl --user status shani-shell`) and are killed right after
the switcher. The island's ask field, left in "Enter to send, Esc to close"
mode for the same stretch, is closed with `closeChronoa`.

Verified live (`dismissAll` rc=0, `state` intact, no QML errors) and in the
full 98-shot pass.

### 2026-11-03 (time-zone map) — setup and Settings pick a zone by clicking the world

Setting the time zone was a text box: you had to know that your city's zone is
spelled `Asia/Kolkata`. The first-boot wizard's time page and **Settings >
Date & language** now carry the same clickable world map — click where you are
and the shell changes the zone with `timedatectl` (the polkit agent asks once).

**Data.** `setup/world-land.js` is 128 coastline rings, 5143 points, 71 KiB —
Natural Earth 1:110m land (public domain, no attribution required), fetched as
GeoJSON and rounded to 0.02°. `tools/make-world-map.py` regenerates it and
writes **both** copies at once (the wizard and the shell are separate configs
with no shared import path, so each carries its own — the same duplication the
two `Common/` trees already have; the generator is the single source).

**Projection.** Equirectangular, cropped to **latTop 84 / latBottom −60**: a
full −90..90 map draws Antarctica's coastline as a heavy full-width bar that
says nothing and costs a fifth of the height. 84 north still reaches the last
settlements (Longyearbyen, northern Greenland). The widget reports its true
aspect (`360 / (latTop − latBottom)`) so callers give it the right box.

**Click → zone.** A click reports lat/lon; the caller picks the nearest
representative city from `/usr/share/zoneinfo/zone1970.tab` (falling back to
`zone.tab`), weighting longitude by `cos(lat)` so the frame narrows towards the
poles where a degree is shorter. The marker and its city pill follow the live
zone, so the map also answers "where am I set to?". The search box stays above
it for people who would rather type.

**Colours.** The sea is the card, the land the accent, the graticule a faint
line — so the map belongs to whatever palette is in use rather than shipping a
green-and-blue picture that fights the amber (night-side shading was tried and
removed: in this crop it is a hard rectangular seam, not a soft terminator).

**Test false alarm.** The new `accent-follows-cold-wall` check first failed with
the accent stuck at the dusk colour. Not a shell bug: `wallpaperDark` defaults
to the bundled dusk wall and overrides the single `wallpaper` key while the
style is dark, so a test that set only `wallpaper` never showed the cold wall.
Clearing `wallpaperDark`/`wallpaperLight` in the check gives the honest answer
(`#5588e7` for a blue gradient). The default dark desktop is still the amber
dusk, accent `#f68f46`.

## 2026-10-30 — Settings UX pass: every setting honest, every useful one surfaced

### Surfaces that were hidden but already wired
- Bar: click-through toggle, hide volume/brightness glyphs
- Displays: auto-rotate (tablets/convertibles with an accelerometer)
- Search: launcher ignores the pointer, hides navigation hints
- Input: compose key, Caps Lock remap
- Date & language: show calendar events
- Personalisation: dark style now toggle, night light on toggle
- Power: dim stage + battery timings + lock-before-suspend
- Apps: screenshot format, recording area/sound

### Dead keys given real consumers
- `screenshotQuality` (grim `-q` in Annotate's drawing save)
- `clipboardOutputFormat` (wl-copy `--type` + ImageMagick conversion)
- `screenshotAnnotationTool` (Screenshots notification launches satty or swappy)
- `bluetoothAutoConnect` (BtAgent reconnects audio/input devices)
- `batteryLimit` (synced with sysfs charge_control_end_threshold)

### WIP files fixed
- `SettingsDevTools.qml`: install check now queries the correct object (was writing `parent.checked` on the Process)
- `Traffic.qml`: replaced per-2s `cat /proc/net/dev` fork with FileView + Timer

### About page
- Two-tap "Reset all settings to their defaults" using `Settings.defaults`

### Keyword lists
- Expanded each category's `words` so Settings search finds the new and existing settings.

## 2026-10-31 — Settings UX overhaul: find, spot, reset

### The search became a command bar
Typing in Settings no longer just filters the 21 category tiles: it matches
individual settings by name/hint/keywords (`SettingsIndex.js`), shows each
match with its current value and an amber dot when it differs from the
shipped default, and activates it by opening the right category and flashing
the control (`Ui.flashSetting`, longest significant word matched against the
control's accessible name). Enter jumps to the first match; Space/click
activates; results are keyboard-navigable in the window (`SettingsWindow`
sidebar has its own MatchList). The category tiles and the window's sidebar
show the same amber dots.

### Customised awareness + safe reset
- Amber dot on a category whose settings differ from the defaults.
- "N customised · Reset this section" strip on every category page — resets
  **scalar** keys only; custom lists (dock pins, window rules, automations,
  world clocks…) survive a section reset. Two-tap confirm, 4 s timeout.
- Counts are computed when the page opens and after a reset (timer every 2 s),
  never per keystroke.
- About keeps the full "Reset all settings".

### Missing settings, all wired to real consumers
- `weatherUnits` °C/°F — Open-Meteo request + the sidebar/desktop `Weather.summary`.
- `weekStartsOn` (Monday|Sunday) — Calendar re-lays its grid and weekday headers.
- `powerSaverAt` (10/15/20/30 %) — Power's low-battery saver threshold (was hardcoded 20).
- `dndWhileLocked` — pop-ups held while the screen is locked (critical still show; apps allowed through DND still come through).
- `notifHideContent` — privacy mode for pop-ups and the sidebar: the app is named, the message is not; inline reply, links, actions and the sender picture hide with it. Critical still shows.
- `recordFps` (auto|30|60) — wf-recorder `-r` when set.
- `reduceTransparencyOnBattery` — Glass becomes opaque and all blur surfaces stop (`Settings.blurWanted`) while on battery; battery state mirrored into Common/PowerState (Common cannot import Services).

### Deliberately not added
- Bar position (top) — by design (Island grows downward); keyboard backlight
  timeout, cursor/screenshot cursor — hardware/niri-config territory, not a
  shell setting; per-app notification snooze defaults — the 5/10/30/60 chips
  cover it; "Do not disturb while fullscreen" — that switch exists
  (`quietWhileFullscreen`).

### Notes / pitfalls
- `JSON.stringify` of the control-centre adapter is the equality oracle for
  "changed"; arrays/objects are treated as customised whenever present
  (never compared) — they are also never reset by a section reset.
- Quickshell reloads Settings pages on file change: SettingsIndex.js changes
  apply without a shell restart.

## 2026-11-01 — Network / Bluetooth / modem / PipeWire deep pass

### NetworkManager (nmcli) — settings that were not wired, now are
- **Hotspot**: `hotspotName` ("" → `<hostname>-hotspot`) and `hotspotBand` (auto / 2.4 / 5 GHz) feed `Net.setHotspot`. The sidebar tile still toggles it; the page says what it will be called.
- **Random MAC on Wi-Fi**: `wifiMacRandom` rewrites `802-11-wireless.cloned-mac-address` (random ↔ preserve) for every saved wireless network, on toggle.
- **Wake on LAN**: `wakeOnLan` sets `802-3-ethernet.wake-on-lan` (magic ↔ default) on every saved wired network.
- **Bluetooth at sign-in**: `bluetoothOnBoot` powers the adapter at login (Net applies it 1.5 s after start).
- **Bluetooth files folder**: `obexDir` → bridge/obex-agent.py now takes an argv dir (and creates it); ObexReceive restarts the agent on change.
- **Saved networks**: the list now includes Bluetooth PAN tethering (`bluetooth` type) with its own icon and the same autoconnect / metered / forget controls; gsm rows gained an APN field and a "use data only at home (no roaming)" switch.
- **Mobile data section** (visible when `Net.hasModem`): operator, signal, state, the WWAN radio toggle, and a note that APN/roaming are per-connection in the list above.
- **VPN section**: lists every VPN/WireGuard connection with Connect/Disconnect and "Connect automatically" (NM `connection.autoconnect`), read live via a Process.
- Everything else (MTU, static routes, addresses, profiles, VLANs) stays in `nm-connection-editor`, which the page still opens.

### BlueZ (bluez-utils 5.87) — audit of what the shell already does
Already wired and honest: adapter power (tile + on-boot), auto-connect (BtAgent), pairing/discovery (SidebarDetails), auto-reconnect of audio/input devices, OBEX receive (now with a folder), OBEX send (BtSend), per-device battery warnings, Dynamic Lock, phone calls/SMS via Chronoa, Bluetooth tile. **What the image ships**: bluetoothctl, btmgmt, btmon; **not** sdptool, hciconfig, pand, rfcomm, obexctl — so hotspot sharing of the PC's connection over Bluetooth (NAP server) is **not** offered (it would need a NAP server NM does not provide). Bluetooth tethering **to** the PC is offered through the saved-networks list above.
- `obexDir` is the one new setting here, since the bridge previously hard-coded `$XDG_DOWNLOAD_DIR`.

### PipeWire (1.6.10) — audit
Already complete: default sink/source switching, per-app volume and per-app output routing (`pw-metadata`), volume (up to 150 %), balance, mute, mic level, noise suppression (RNNoise), loudness (LUFS), crossfeed, stereo widening, equaliser + presets, AutoEq, impulse response, compressor, device profiles, screen-share detection, mic-in-use. **Nothing further to wire honestly** (no `libcamera` in the image, and echo cancellation would need a WirePlumber config fragment the shell does not own).

### ModemManager
The shell talks D-Bus through `bridge/modem.py` (no mmcli in the image). Surfacing the operator/signal/state read-out and the per-connection APN/roaming controls above is the honest coverage; network mode and PIN management stay with ModemManager's own tools.

### Notes
- `Net.hasWifi`/`Net.hasModem` gate the Hotspot and Mobile-data sections, so they vanish on machines without the hardware — honest.
- SettingsIndex.js gained the six new network keys and their group entries.

## 2026-11-02 — More useful settings: keyboard backlight, touchpad, recording, notifications, lock screen

### Keyboard backlight (new service KbdBacklight)
- `kbdBacklight: "auto" | "on" | "off"` — Settings > Keyboard & input, plus a sidebar tile ("Keyboard backlight") that flips it on/off by hand (and overrides auto).
- Auto mode: follows the ambient sensor (on under 40 lx) or, with no sensor, on between 19:00 and 07:00.
- Device found via `brightnessctl -l` (the `*kbd*`/`*keyboard*` LED class device, e.g. `tpacpi::kbd_backlight`); writes with `brightnessctl -d <dev> set <level>`.

### Touchpad (niri 26.04 exposes these; the shell did not)
- `tpMiddleEmulation`, `tpDragLock`, `tpTapButtonMap` ("lrm"|"lmr") added to Settings, InputConfig.kdl (`middle-emulation`, `drag-lock`, `tap-button-map`) and the Keyboard & input page. Touchpad gestures themselves are niri's and not individually configurable in 26.04 (documented in GAPS.md).

### Screenshots & recording
- `screenshotCopyImage` (default on) — the captured picture is copied to the clipboard automatically (`wl-copy --type` by extension), on top of the saved file.
- `recordCodec` (auto / H.264 / HEVC / VP9 / AV1) — wf-recorder `-c <codec>`.

### Notifications & lock screen
- `snoozeMinutes` (5/10/30/60) — the "Snooze" action on a notification waits that long (was hardcoded to 60).
- `lockScreenMedia` — gates the now-playing controls on the lock screen.

### Notes
- All new keys are scalars, so they show a customised dot and are reset by "Reset this section".
- Keyboard backlight auto follows AmbientLight when present; otherwise the clock.

## 2026-11-03 — Folder pickers instead of bare paths
- Settings that take a directory (slideshow, screenshots, recordings, Bluetooth received files) now have a "Browse" button opening a Qt Quick `FolderDialog` (xdg-desktop-portal-gtk on niri) on top of the existing text field, so the path can be picked instead of typed. The text field stays for typing/pasting.

## 2026-11-04 — Folder/file pickers instead of bare paths
- Settings that take a directory (slideshow, screenshots, recordings, Bluetooth received files) now have a "Browse" button opening a native FolderDialog (xdg-desktop-portal-gtk on niri) on top of the text field; the field stays for typing/pasting.
- Settings > Sound: the AutoEq and impulse-response paths now have a "Browse" button (FileDialog) on top of the text field.

## 2026-11-05 — Terminal picker + more user-friendly configs
- The terminal setting is now a dropdown of installed terminals (foot, kitty, alacritty, …) detected at runtime, plus "Other…" that reveals a text field for anything not installed — instead of a bare text input.
- JPEG/WebP screenshot quality converted from a bare 0–1 slider to choice chips (60/75/85/90/95/100 %).
- Directory/file settings (slideshow, screenshots, recordings, Bluetooth received files, AutoEq, impulse response) gained "Browse" buttons opening native folder/file pickers, alongside the text field.

## 2026-11-06 — Touchpad gestures (niri's dnd-edge-*), keyboard backlight, more user-friendly configs
- Touchpad gestures: `dndEdgeViewScroll` and `dndEdgeWorkspaceSwitch` now control niri's `dnd-edge-view-scroll` / `dnd-edge-workspace-switch` (moved the `gestures { hot-corners { off } }` block into the shell's generated `shani-input.kdl` so all three live together; session.kdl no longer declares gestures). Validated by `niri validate`.
- Keyboard backlight: new `KbdBacklight` service + `kbdBacklight` setting (auto/on/off) + sidebar tile; auto follows the ambient sensor or the clock.
- Touchpad: middle-emulation, drag-lock, tap-button-map (left-right-middle / left-middle-right).
- Terminal picker: dropdown of installed terminals + "Other…".
- JPEG/WebP quality: choice chips instead of a bare slider.
- Directory/file settings: "Browse" buttons (FolderDialog/FileDialog) on top of the text field.

## 2026-11-07 — Idle, lock screen and more user-friendly configs
- `dimAfterBattery` (dim sooner on battery) — Idle now has a battery-specific dim stage (previously only lock/screen-off/suspend did).
- `lockScreenClock` and `lockScreenBlur` — the clock and the wallpaper blur on the lock screen are now toggles (Privacy > Lock screen).

## 2026-11-08 — More user-friendly configs (continued)
- `dimAfterBattery` (dim sooner on battery), `lockScreenClock`, `lockScreenDate`, `lockScreenBattery`, `lockScreenBlur`, `lockScreenMedia` — lock screen and idle now fully configurable.
- `autoLockOnLowBattery` — lock the screen at 7 % battery.
- `doubleClickSpeed` — GTK double-click time (slow/normal/fast/fastest), written via gsettings.

## 2026-11-09 — First-boot setup: clickable step rail, pickers and review
- `setup/shell.qml` redesigned: a clickable step rail (welcome → keyboard → network → time → account → done) with icons and click-back, plus dots on narrow screens; the furthest step reached is the limit. Nothing is typed from memory.
- Language page: quick-pick chips for the languages the wizard itself speaks, then a searchable list of every locale on the system; the list now scrolls to the chosen locale on load and after switching. Default locale no longer falls back to the alphabetically first one (`aa_DJ.utf8`): it follows `LANG`/`localectl`, then US English, then any English, then the first available.
- Keyboard page: quick-pick chips for the usual layouts, the chosen ones shown with remove buttons, a field to try a layout, and a search over the full xkb catalogue.
- Network page: refresh button, connect button alongside password entry, show/hide password toggle, continue-without-internet action (now an outlined button instead of plain text); online status shown.
- Time page: quick-pick chips for common zones, click-the-map, search field, and the time in the chosen zone.
- Account page: avatar initials, password strength bar with colour, show/hide toggle, name suggestion, computer-name suggestion (no longer produces "shani-shani" for a user named Shani), an admin note, and a two-line review summary. Next/Start button enable guards.
- `setup/strings.js`: 62 keys in six languages (en, mr, hi, de, es, fr), all matching the English set.
- Fixed fatal `Matugen.qml` uppercase property `B` → `b` (and the one reference), which had blocked the whole setup from loading.
- Removed the unnecessary `qs.Services` import from `shani/Common/AppPicker.qml` (DesktopEntries resolves via `Quickshell`), clearing the only remaining scanner warning in setup.
- All 14 checks in `dev/setup-test.sh` pass with the greeter KDL mounted.

## 2026-11-09 — UI/UX improvements: empty states, search highlighting, privacy dashboard
- Added `shani/Common/EmptyState.qml`: icon + title + subtitle + optional action
  button, used where lists/panels would otherwise be blank.
- Added `shani/Common/HighlightText.qml`: highlights every occurrence of the
  search term inside a label.
- Settings search now highlights the matched term in each result row
  (`SettingsMatchList`), and shows an empty state with suggestions when nothing
  matches.
- Settings > Network shows an empty state when no networks are saved.
- Settings > Search shows an empty state when "File names" is on but no folders
  are configured.
- Settings > Privacy gained a privacy dashboard: a one-glance summary of which
  apps hold camera/microphone/location/screenshot/background permissions, with
  per-category counts.
- Setup wizard: time page now shows the nearest city and the time in the chosen
  zone under the zone name; done page greets the new user by name.
- Setup wizard default locale no longer opens on `aa_DJ.utf8`.
- Documented a UI/UX improvement backlog and design references (Deepin, Pantheon,
  Cutefish, macOS, Windows, Android, custom ROMs) in `docs/UX-IMPROVEMENTS.md`.

## 2026-11-11 — A file manager of our own, and a shell that starts at all
- **The Files surface** (`shani/Modules/Files/FilesPanel.qml`): the places on
  the left, the folder as a grid of tiles or a list of rows, a search box, a
  preview of what is chosen. Click to choose, Ctrl-click for more, Shift-click
  for a range, Enter or a double click to open, F2 to rename, Delete to the
  trash, Backspace up, Escape closes. The folder is **watched** (inotify), so a
  file made or removed elsewhere shows up at once.
- **The backend** (`bridge/files.py`): `list`, `watch`, `stat`, `mkdir`,
  `rename`, `trash`, `places`. One JSON object per answer; the watch answers
  one per change. The trash is the **desktop trash** (`gio trash`), so anything
  moved there can be put back — the file manager never deletes.
- **The model** (`shani/Common/FileDirectory.qml`): the listing, the name
  filter, and the watch (a python process, alive only while a folder is open).
- **The chooser** (`shani/Services/FilePicker.qml` +
  `Modules/FilePicker/FilePickerPanel.qml`): the shell's own open/save/folder
  picker. `Common/FolderPicker.qml` now uses it instead of the native dialog,
  which was the desktop portal's and **held the whole shell while D-Bus waited
  for the portal**.
- Wired in: the launcher's "Files" action, `Super+E`, `shani files …` and
  `shani picker …` on the CLI, `Ui.files`, and `state` (`filesShown`,
  `filesPath`, `filesEntries`, …).
- **The shell did not load at HEAD** — before any of this, `qs` refused to
  start. Fixed: `TrimOpen`/`TrimCut` (upper-case IPC names), a duplicate
  `notesOpen`, a duplicate `notesNotebook` in `Common/Ui.qml`,
  `import qs.Modules.LocalSend` (a file, not a directory), `function print()`
  in `Services/PdfViewer.qml` and `Services/QuickNotes.qml`,
  `Keys.onBackspacePressed`/`onHomePressed`/`onEndPressed` (not real Qt
  signals), `TabBar.delegate`/`tabDelegate`, `Theme.radiusLg` and
  `Theme.onSurfaceVariant` (dux's token names), `const` at QML object scope,
  `TextArea`'s `cursorPositionChanged` handler declared twice, and
  `placeholderText`/`flat`/`checked`/`readOnly` missing from our own
  `Common/TextField.qml` and `Common/Button.qml`.
- 303 unit tests pass (`tests/test_files.py` is new: the backend's contract for
  real, the JS helpers in node, and the wiring). The nine checks added to
  `dev/shell-test.sh` (listing, watch, new folder, rename, trash, the chooser's
  answer) all pass.
- The Files surface and the chooser are **overlay** (layer-shell) surfaces, and
  the nested niri shows no Overlay layer: they cannot be photographed there,
  like the Disktree panel. Noted in `GAPS.md`.
- `docs/UX-IMPROVEMENTS.md` §12: what else dux (DMS) has that we could take —
  the plugin system, the pure-logic helpers, the widgets, and what not to take.

## 2026-11-11 — The cheap half of what dux has: the shared helpers
- **`Common/Contrast.js`** — WCAG luminance, ratio and "which ink reads on
  this". `Services/Color.qml` had its own copy of the maths; it uses the
  shared one now. `Theme.accentInk` is measured (`readableOn`) instead of
  guessed from the accent's lightness: a pale accent takes dark text, a deep
  one takes white, and the switch happens where the contrast says.
- **`Common/Shape.js`** — the corner scale, carrying the shell's own radii
  (s = 10, l = 16, xl = 22). `Theme.radius*` comes from it, and the hardcoded
  `radius: 10` / `radius: 8` in `Common/` (button, field, list row, screen
  keyboard, hints, pickers) are tokens now. The look is unchanged: the
  Settings render before and after differs by 0.18 % of the pixels (the clock
  and the focused button).
- **`Common/WheelInput.js`** — a wheel notch is one step, a finger slides by
  its own pixels. `Common/SliderRow.qml` used to move 5 % per *pixel* of
  finger movement; it moves 5 % per 40 pixels now, and a notch is still 5 %.
- **`Common/Proc.qml`** — run a command with a debounce and a timeout: a burst
  of calls runs once, and a command that hangs cannot wedge the shell.
  `Services/Disktree.qml` uses it for the disk walk (a minute's grace);
  `Services/Files.qml` keeps its own one-at-a-time queue and gained a
  watchdog (20 s) on top.
- **`Common/Log.qml`** — `Log.scoped("Files")`: a line with a name on it,
  quiet by default, `SHANI_LOG=Files,Audio` to name the ones that should
  speak, `SHANI_LOG=Files:debug` for the details.
- **`Common/Hct.js` + `Tonal.js` + `Accents.js`** — Material's colour space
  (Apache-2.0, the notice beside them). In the tree and tested, **not
  wired**: ranking a wallpaper by chroma picks the Saturn ring's lavender
  over the planet's amber, and the accent is meant to be the brand's amber.
  Deriving the palette is a design decision, not a port.
- **`tests/test_shell_helpers.py`** — the helpers in node (a small loader
  turns QML's `.import "X.js" as X` into plain namespaces, and a `Qt` shim
  stands in for the colour calls), plus a check that the shell really uses
  them. 315 unit tests pass.
- **Fixed: the Disktree panel never opened.** `Services/Disktree.qml` had a
  property called `root` and an id called `root`; `root = dir` inside
  `open()` was not an lvalue, so the scan never started (the property is now
  `scanRoot`, and `state` reports `disktreeRoot` from it).

## 2026-11-11 (later) — The shell's surfaces become apps, and a tree that loads again
- **The working tree did not load.** A round of additions after the entry
  above left `shell.qml` with a duplicate IPC method, duplicate properties in
  `Services/Files.qml`, `Component.onCompleted` set twice in the Processes
  panel, a second "About" page in `SettingsPage.qml` written with another
  shell's types, and imports of single files as modules. All fixed; the
  load is clean and the unit tests are back.
- **Taken out, because they could not work as written** (kept, outside the
  repo, in `../shani-shell-parked-2026-11-11/`): a Battery Health centre
  (`pkexec sh -c` with the values never passed; Settings > Power already has
  health and the charge limit through `shani-admin.py`), a speed test (eight
  parallel transfers against another project's server), a video wallpaper
  (mpv as an ordinary window, which niri tiles), recorder click rings (a
  `MouseArea` in a singleton sees no clicks; a 16 ms timer ran forever), a
  camera "mic meter" (it read the volume setting, and its "No audio" switch
  did not stop the microphone), theme presets (not valid JS), and a native
  annotation panel that did not parse — screenshots annotate with satty again.
- **Files: copy, move and duplicate pass argv.** They built `sh -c` strings
  from file names; a name with `$(…)` in it ran. Now `cp -rn -- …` / `mv -n`.
- **Settings > "Changed this session"** (below the category list): what was
  changed since sign-in, by the name the search uses, each with Undo. The
  snapshot it undoes to is taken *after* the file is read; taken at
  construction it was the defaults, and Undo would have discarded older
  choices.
- **The shell's apps** (`bin/shani`'s `APPS`): one table feeds `shani app NAME
  [FILE]`, the desktop entries the package writes (`dev.shani.*.desktop`, 17
  of them — the launcher's app list, dock pins, "Open with", default apps),
  and `dev/shell-parts/apps.sh`, which opens every one in the live shell and
  fails on any QML error written while it opens.
- **That test found six surfaces that had never been visible**: Notes,
  Scanner, Passwords, Kundali, LocalSend and the video player import
  `qs.Services as Services` and said `Lock.locked` — a ReferenceError inside
  `visible:`. Also: the Calendar's week view called four members of its own
  and nine of `Agenda` that did not exist (the week view is finished on real
  data; the calendars/online-accounts sections, which had no backend, are
  gone); `Camera.open()` called a bool (the launcher's Camera action and the
  sidebar tile did nothing); the Files grid's `grid.columns`; `parent: win`.
  `tests/test_wiring.py` now guards theme tokens and service references.
- **Text Editor, rebuilt** on `Services/TextDocs.qml`: the documents outlive
  the panel (Escape or a click outside no longer discards what was typed),
  saves are atomic and keep permissions, links and CRLF, a binary file, a
  folder or a file over 2 MB is refused and said. Before: the save handler
  was assigned to a signal (never ran), shortcuts sat on a sibling of the
  editor (never reached while typing), and opening a file marked it modified.
  It is the image's default for text files (`mimeapps.list` named
  `org.gnome.TextEditor`, which the niri image no longer ships).
- **Packaging**: the PKGBUILD's hand-kept list of bridge scripts left out
  `screensaver.py` — which `chronoa-bridge.py` imports, so the *packaged*
  bridge died at import — and `characters.py`, and `data/whats-new.md` was
  never installed. It installs `bridge/*.py` by glob now, and
  `tests/test_packaging.py` runs the real `package()` and checks the result.
  `matugen` (Adaptive palette, Aether) is a dependency of shani-desktop-niri.
- **Handing off to apps the image has**: a scanner's "Scan" and a capture
  card's "Camera" open the shell's own surfaces where SimpleScan / Snapshot
  are not installed; "Passwords and Keys" is started by its desktop entry
  (a Flatpak here: there is no `seahorse` on the path).
- **The sidebar's alarm time chips** show only while an alarm is being added
  (they were forty keyboard stops ahead of the notifications; a notification's
  action took more than 60 presses of Down, now 33). The button beside
  "Alarms & stopwatch" opened the character browser; it adds an alarm.
- **Idle memory**: the apps and other rarely opened surfaces are read on first
  open (`LazyLoader { source: … }`): 527 → 512 MB idle, under the 520 budget.

## 2026-11-11 (night) — The apps are windows
- **`Common/AppWindow`**: every app of the shell's is a niri window now, as
  Settings already was - it tiles or floats, is in Alt+Tab and the overview,
  several are open at once, and opening the launcher or the sidebar no longer
  closes it. Before, each was a full-screen overlay holding the keyboard, one
  at a time. 23 panels were converted (a script for the common header, the
  rest by hand); `Ui.closeAll()` leaves app windows alone, `Ui.closeApps()`
  (the IPC's `closeAll`) closes them.
- **Each window has its own identity.** Every Quickshell window reaches niri
  as `org.quickshell`; `Services/Niri.own()` gives each the id of its desktop
  entry by its title (`ShellApps.js`, kept equal to `bin/shani`'s `APPS` by
  `tests/test_apps.py`), so the dock, the switcher and the bar show the app's
  icon and name. Small utilities float at their own size (a niri window rule
  by title); Files, the editor and the viewers tile.
- **Seeing them for the first time found more** (the overlay layer cannot be
  photographed in the nested session; windows can): Maps showed "Access
  blocked" on every tile - Qt's user agent is refused by OpenStreetMap, so
  tiles are fetched with curl under the shell's own, into a cache; Characters
  was empty in the test session; the System Monitor's process rows were drawn
  on top of each other (a Repeater of heightless Items; a ListView now);
  Scanner, Passwords, Kundali, LocalSend and Notes had white stock controls
  (AppWindow sets the palette); the Calculator was a column wide.
- **Media Player** (`Modules/MediaPlayer`, `Services/PlayQueue`): QtMultimedia
  (FFmpeg). Play, pause, seek, the folder's other files as the queue, volume,
  speed, repeat, shuffle, full screen, drop a file on it. It replaces the
  panel that started `gst-play-1.0` in a bare window. The suite makes two
  clips and a song with ffmpeg and plays them: position moves, pause holds,
  seek lands, Next goes on, a text file is refused.
- **Archives** (`Services/Archive`, bsdtar): lists and extracts into a new
  folder beside the archive or in a chosen one; never writes over what is
  there. **Clocks**: world, alarms, stopwatch, timer in one window, on the
  services the sidebar already used.
- **Text Editor colours** (`Common/Highlight.js`): drawn under the text being
  typed, which is see-through; a test holds that no character is lost.
- **Calendar sources**: `agenda.py calendars` lists EDS's calendars; the ones
  hidden are left out of the agenda, the Calendar and the reminders.
- **Defaults** (`shani-desktop-niri`'s `mimeapps.list`): the shell's app first
  for video, audio, pictures, PDF, text and archives, the Flatpak after it.
  `shani-shell` depends on `qt6-multimedia`, `qt6-multimedia-ffmpeg`,
  `libarchive`.

## 2026-11-12 — A header of its own, one place for each thing, and the gaps filled
- **No more white title bar.** Qt's own decoration (QT_WAYLAND_DECORATION
  "adwaita", meant for other Qt apps) drew a white bar over every shell
  window. It is off for the shell's process (QT_WAYLAND_DISABLE_WINDOWDECORATION,
  shani-shell.service and the test session) and `Common/AppWindow` draws a
  header in the shell's colours: icon, the file and the app's name, the app's
  own buttons (`tools:`), minimise, maximise, close; drag to move, double-click
  to maximise, the edges resize a floating window. Settings is an AppWindow
  too. In-app "×" and "Close" buttons that duplicated it are gone.
- **The Media Player is an MPRIS player** (`bridge/mpris-player.py`): the
  bar's now playing, the sidebar, the lock screen and the media keys read
  MPRIS, and never saw what the shell itself played. Checked live: the media
  key pauses it. `tests/test_mpris_player.py` runs it on a private bus.
- **One place for each thing.** The sidebar's weather line opens Weather; its
  alarms section has "Open Clocks"; the bar's and the Island's timer and the
  timer tile's detail open Clocks' timer; the desktop clock opens Clocks and
  the weather card Weather; the sidebar's screen time opens Screen Time; its
  notes open Notes (they asked Chronoa before); now playing can raise any
  player that can be raised. Checked live through AT-SPI.
- **New apps from the survey** (`docs/ECOSYSTEM.md`): Weather (GNOME Weather
  left the niri image with nothing in its place), Screen Time, Tasks (EDS task
  lists, `bridge/tasks.py`; checked live: add, done from elsewhere, delete),
  Photos, Translate (the local model), and entries for the action tools.
- **LocalSend taken out.** Its panel broadcast a made-up discovery message (no
  LocalSend device answers it), sent with `requests` and ran an HTTP server
  that took uploads from anyone on the network into ~/Downloads. Parked in
  `../shani-shell-parked-2026-11-11/replaced/`; a real one is a gap.
- The app-filter check searched "Files", which is now two apps (Nautilus and
  ours); it uses Clocks.
- **Settings things moved into Settings.** Screen Time, Disk Cleanup and
  Wallpaper & Style were apps; every other desktop keeps them in its settings.
  They are now Settings › Screen time, › Storage and › Personalisation
  ("Colours from a picture"), and Nearby Share's "Visible to devices nearby"
  is a switch in › Sharing. Their IPC (`screenTimeOpen`, `cleanUpOpen`,
  `wallpaperStyleOpen`, `themeFromImage`) opens those pages; `Ui.openSettings`
  takes a section to scroll to. Battery health was already in › Power. The
  old windows are parked in `../shani-shell-parked-2026-11-11/moved-to-settings/`.
- **The test session had accessibility off.** An edit to `dev/session.sh`
  put `QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1` inside the comment after the icon
  theme's export, so a part run alone (`shell=apps`) found nothing over
  AT-SPI and the sidebar "Open Clocks" press failed with "0 on-screen
  matches". Fixed; the check now prints the press's own words when it fails.
- State keys `secrets`, `signed` and `trim` were the old names of Password
  Generator, PDF Signer and Video Trimmer; renamed to `passwordGenerator`,
  `pdfSigner` and `videoTrimmer` (the load-on-open check asked for those and
  failed).
- **Windows open and close with niri's custom shaders** (Settings › Windows ›
  Look and motion, `Services/WindowLook.qml` → `~/.config/niri/shani-look.kdl`):
  Glide (rises 3.5% and grows from 88% while fading in; sinks away),
  Pop (a spring from 72%, damping 0.62: a small bounce), Dissolve (5 px
  grains swept from the top left, the accent glowing along the moving edge),
  or Plain (niri's own). Also the speed (niri's `slowdown`), the shadow (none,
  soft, deep), the corners (0-18 px) and the frosted glass (blur passes, with
  `saturation 1.25` and `noise 0.02` against banding). The include is the
  config's last line: niri lets a later window rule win, and the config's own
  12 px corner rule comes after the other includes. The animations block moved
  here from InputConfig (one writer). Checked live (`shell=window-look`): each
  style loads, niri logs no shader error, and windows photographed mid-open and
  mid-close at slowdown 12 show each effect; corners stay rounded mid-animation.
- **The default scratchpad lost its name.** An icon-name sweep turned the
  `name: "terminal"` of `scratchPads` into `"utilities-terminal"`, so Mod+`
  (`scratchpad terminal`) found nothing; put back.
- `dev/shell-parts/zz-tab.sh` was a leftover isolation copy of the tablet
  checks; in a full run the tablet had been greeted already, so it failed.
  Parked. The PDF Signer's name had become "PDF PdfSigner" in the rename.
- **The terminal, measured and set up** (2026-11-12). In the nested niri, 5
  windows each: `footclient` (foot server) 92 ms to the first window and 35 MB
  for five; foot, a process each, 335 ms and 60 MB; Ghostty 1.4.0 1577 ms and
  969 MB (software GL in the container inflates a GPU terminal - on a real GPU
  published figures are 60-100 MB); kitty 0.50 opened no window there. Foot stays
  the default, now as footclient: shani-desktop-niri enables
  `foot-server.socket` for every user and lists footclient.desktop first in
  `niri-xdg-terminals.list`; Mod+Return spawns `xdg-terminal-exec`, and
  `Services/Terminal.qml` writes `~/.config/niri-xdg-terminals.list` from
  Settings › Apps & files, so the bind, the shell and every app open the same
  terminal. Ghostty is offered there (Flathub) when not installed.
- **foot in the desktop's colours.** `Services/Terminal.qml` writes
  `~/.config/foot/foot.ini` - an include of the system file plus the theme's
  background, text, accent (cursor, selection, links) and the shell's header
  colour for the titlebar - only while its first line is the shell's mark (a
  person's own file is left alone; checked live, as the negative control). Open
  windows follow light/dark at once: SIGUSR2 is foot's light, SIGUSR1 its dark
  (measured by pixel, and foot survives both). The titlebar and the accent are
  read when foot starts, so an idle foot server is stopped after a change and
  the next window, socket-activated, has them (checked: a new window's titlebar
  is light after the switch). `foot --check-config` refuses a missing include
  (exit 230), so the file never includes anything optional.
- **Chronoa from the terminal.** foot's `pipe-command-output` (Ctrl+Shift+A)
  and `pipe-selected` (Ctrl+Shift+E) run `shani chronoa explain -`, which reads
  stdin (`-` for any TEXT argument now), strips colour escapes and opens the
  panel asking what the output means. The last command's output needs the
  shell's OSC 133 marks: shani-settings' `terminal.zsh`/`terminal.bash` send
  them, with OSC 7 (new windows in the same folder) and the title (the folder,
  or the running command).
- **Device greetings "only failed in the full run" - harness orphans.** The
  suite restarts the shell early; it killed `qs` alone, so its plugwatch lived on
  (reparented to PID 1, seen with ps) beside the new one, and the fake monitor's
  `cat` outlived its script too - both reading the udev FIFO, eating events: one
  run lost only the first tablet, another every device (13 failures). On a real
  system systemd kills shani-shell.service's whole cgroup, so this is the
  harness's: `stopshell` now stops the shell's bridges with it, and
  `dev/fake-udevadm.sh` reads with the shell's own `read` (no child to orphan).
  Checked with a probe of the same restart: nothing left over, the tablet greeted.
