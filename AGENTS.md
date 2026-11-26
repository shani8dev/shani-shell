# AGENTS.md - shani-shell

ShaniOS's niri desktop: one Quickshell (QML) shell with its own apps, settings,
phone, system pages and Chronoa surfaces. **No GTK** anywhere in it.

## Shared architecture (all repos)

One implementation per capability, logic out of UI code, every UI and the
assistant built on the same services: the plan is
`docs/SHARED-ARCHITECTURE.md` (canonical for every ShaniOS repo), and this
repo's part is `docs/SHARED-PLAN.md`. Read both before changing a backend, a
CLI, a device engine or a settings page, and do as much of this repo's part
as your task allows.

## Layout

- `shani/` the shell (`shell.qml`, `Common/` components and Theme, `Services/`
  singletons, `Modules/` apps and surfaces); `greeter/`, `setup/` share `Common`.
- `bridge/` Python commands the QML runs (argv in, JSON out); `bridge/phone/`
  the device engines (the seed copy: fix them here).
- `bin/shani` the `shani` CLI (apps table, `shani app`, software, calls/messages).
- `dev/` the harness; `tests/` pytest.

## Verify by execution

- Unit suite: `python3 -m pytest -q -p no:cacheprovider` (about 20 minutes).
- Live checks in the dev image (Docker `shani-shell-dev`, nested niri):
  `sh dev/check.sh shell=<part>` with parts in `dev/shell-parts/<part>.sh`;
  results are `RESULT name PASS|FAIL` lines in `out/logs/check-shell-<part>.log`,
  screenshots in `out/shots/` (look at them). `render=matrix[:kinds]` renders
  every screen kind. A phone: `SHANI_WIDTH=412 SHANI_SCREEN=915`;
  `SHANI_APPS=a,b` limits the apps / apps-phone parts.
- The box has a memory ceiling (`SHANI_CHECK_MEMORY`, 6g): a layout loop once
  took qs to 12 GB and the host's OOM killer chose from the desktop.
- After adding strings: `python3 tools/i18n.py extract`. After adding a
  surface: `python3 tools/surfaces.py check` and `dev/surfaces.tsv`.
- Stand-ins come in through `SHANI_*` overrides (`dev/fake-*`); the system
  pages' harness uses `SHANI_SYSTEM_*` names so it cannot leak into a session.
  A stand-in must reject what the real command rejects;
  `tests/test_os_cli_contract.py` checks every OS-command call against the real
  parser in `../shani-deploy`.

## Rules

- Never `git stash`; never push unless asked.
- UI: every value pickable by click, typing only optional; `Common` components
  and `Theme` tokens only; every clickable has a keyboard path and an
  accessible name; plain words, no other products' names.
- Never open windows on the person's own display; the harness runs nested.
- A width computed from the row it sits in feeds back into itself (a Flow
  whose field width came from the Flow grew without end): give the column the
  width, not the content.
- The landline media engine (`bridge/phone/landline/{ua,media,video}.py`):
  move or rename imports only, never their internals.
