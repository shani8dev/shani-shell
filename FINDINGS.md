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
