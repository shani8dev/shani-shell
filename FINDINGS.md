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
| `dev.shani.chronoa.Agent` | `Turn(text) -> id`, `Approve(id, decision)`, `Event(json) signal` | 🟡 **proposed only** — not in product code |

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

Three niri configs + screenshot crops over terminal text / wallpaper:

- `niri/protocol.kdl` (SHANI_BLUR=1, shell asks via `BackgroundEffect.blurRegion`):
  blurred. ✅
- `niri/rule.kdl` (SHANI_BLUR=0, compositor layer-rule `background-effect { blur true }`),
  namespaces extended to `^shani-(panel|launcher|notifications|chronoa|chronoa-cue)$`:
  blurred. ✅
- `niri/none.kdl`: sharp control → text shows through unsmeared. ✅

Final deliverable state: default blur run uses the protocol path (`SHANI_BLUR=1`,
`niri/protocol.kdl`); layer-rule is the fallback (also updated namespace regex).

## Next moves

- Ship the `dev.shani.chronoa.Agent` turn-stream contract in Chronoa itself.
- Real-app activation path in the container to test `dev.shani.chronoa` actions.
- Sharper final wallpaper (current one is mostly gradient+grid; SHANI wordmark ended up
  under the demo terminal).
- Final hero screenshot with panel + bar + cue in one frame.
