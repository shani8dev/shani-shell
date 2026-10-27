# shani-shell — AI harness shell (Quickshell + Chronoa)

Move from `/tmp/opencode/qs-spike` (container spike) to `~/Documents/shani/shani-shell`.
Status at move: verified end-to-end; QML parses clean; Chronoa D-Bus contracted;
blur verified 3 ways.

```
shani/        Quickshell config: shell.qml + ChronoaPanel.qml + stats.sh
bin/          bridge (chronoa-bridge.py), mock (mock-chronoa.py), session runners,
              measure/shot/blur-test/demo scripts
niri/         compositor variants: protocol (blur via ext-background-effect),
              rule (layer-rule blur), none (control)
assets/       wallpaper (posterized plasma + grid + SHANI wordmark)
shots/        01–17 + blur-compare (bar/panel/approval/reply/blur)
FINDINGS.md   contract findings (Agent turn-stream missing), measurements,
              blink/caveats
```

## Quickshell config path
`qs -c shani` expects `~/.config/quickshell/shani/shell.qml`. Link:
`ln -s ~/Documents/shani/shani-shell/shani ~/.config/quickshell/shani`

## Verified contracts (in `bin/` and `shani/`)
- `org.shani.Chronoa.Mascot` / `.Windows`: bridge owns, calls from Chronoa.
- `dev.shani.chronoa.Agent`: **proposed contract** implemented in mock + bridge;
  needs real Chronoa adoption (`Turn`/`Approve`/`Event`).
- `dev.shani.chronoa.Gateways`: exists; fire-and-forget `Submit`.

See `FINDINGS.md` for measurements, blur comparison, and the Agent-gap
recommendation.
