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

1. **The big one:** Chronoa has no turn-stream API yet. The only inbound surface is
   `Gateways.Submit`, which is fire-and-forget — replies land in Chronoa's own GTK
   window. The proposed `dev.shani.chronoa.Agent` (`Turn`, `Approve`, `Event`) is the
   right harness-side contract; recommend shipping it (turn lifecycle ids, approval
   callbacks, event signal) rather than growing more ad-hoc signals.
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
| Update button did nothing | it opened Cassini, which the niri desktop does not install | Cassini where present, else `pkexec shani-deploy` in a terminal |
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
