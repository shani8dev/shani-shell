# Surface coverage: one catalog, every harness

Every harness is started the same way, `sh dev/check.sh <suite>`, and every
harness script sources the same helpers, `dev/harness.sh` (`ipc`,
`ipc_line`, `st`, `q`, `waitfor`, `result`, `shot`, `settings`,
`settings_merge`). `tests/test_repo_layout.py` fails if a harness defines its
own copy again. The copies had drifted: `waitfor`'s second argument was seconds
in the suite and half-second ticks in the render.

## What "all surfaces" means

The list of surfaces comes from the code, not from the harnesses:
`tools/surfaces.py list` reads `shani/shell.qml` (what it instantiates,
directly, per screen, or behind a `LazyLoader`, with the condition that gates
it). The left rail, behind `Settings.data.leftRail`, was in no render because
coverage used to be counted from what the harnesses happened to capture.

`dev/surfaces.tsv` maps each surface to the captures that show it: render
scenes (`dev/render.sh`), shots from the shell suite (`dev/shell-test.sh`,
`dev/shell-parts/*.sh`) and from the other harnesses (greeter, setup, polkit).
A surface the nested session cannot show has `-` and the reason.

    sh dev/check.sh surfaces       # RESULT surfaces-covered PASS/FAIL
    python3 tools/surfaces.py missing

`tests/test_surfaces.py` fails when `shell.qml` loads a surface that is not in
the catalog, or the catalog names a capture that no harness takes.

## Adding a surface

1. Load it in `shani/shell.qml`.
2. Photograph it: a `capture` scene in `dev/render.sh` (a beauty shot behind a
   state assertion) or a `shot` in the shell part that tests it. A surface
   behind a setting or a passing state goes in render's "surfaces behind a
   setting or a passing state" section.
3. Add its row to `dev/surfaces.tsv`.

## Where output goes

Everything a run writes is under `out/` (git-ignored): `out/logs`,
`out/shots`, `out/renders`, `out/demos`. `dev/render.sh` puts a directory
given outside `out/` under `out/renders/` instead; `tests/test_repo_layout.py`
fails on anything at the top of the repo that is neither tracked nor one of the
ignored places.
