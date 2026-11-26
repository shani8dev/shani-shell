# Shared architecture: one place for every piece of logic

**Canonical copy.** This file (`shani-shell/docs/SHARED-ARCHITECTURE.md`) is the
plan for every ShaniOS repository. Each repo has a short `docs/SHARED-PLAN.md`
with its own part and a pointer from its `AGENTS.md`. Change the plan here and
only here; the per-repo files hold that repo's part, not copies of this one.

Agents: read this before changing any backend, CLI, device engine or settings
page, in any repo. Do as much of your repo's part as your task allows, never
in a way that breaks a consumer, and record what you did in the status table
at the end.

## Goal

The niri edition is one Qt shell with **no GTK**. GNOME, Plasma and COSMIC keep
native GTK windows. Both, plus Chronoa and the command line, use **the same
logic**: a fix or a new capability is written once and every UI, the assistant
and the CLI get it in the same release. Nothing that works today is lost on
the way.

## Where we are (measured 2026-11-26)

- The shell is already GTK-free: 102 QML modules (78k lines), 113 Python
  bridges (37k lines, JSON out, GLib/Gio/Gst only), `bridge/phone` (23k).
- GTK still reaches the niri image through three of our packages:
  `shani-chronoa` (engine and GTK windows in one package; Settings starts the
  GTK app), `shani-link` (pulled in only as Chronoa's dependency) and
  `shani-backup` (a GTK app beside the shell's own Backup page).
- The same logic lives more than once:
  - phone/watch/landline engines in `shani-shell/bridge/phone` **and**
    `shani-link/shani_link` (12+ files already drifted, up to 289 lines);
    two D-Bus services (`dev.shani.Link`, `dev.shani.Shell.Phone`) with two
    data homes, and nothing ships a unit for the shell's one;
  - system logic three times: Cassini's 75 tabs (44k lines, all mixed into
    GTK), the shell's `system_*` bridges, Chronoa/extras skills;
  - every repo writes its own test stand-ins, which accept any argument: the
    shell's "Clean up" ran `shani-deploy --yes`, which the real tool refuses.
- `shani-deploy` already ships the OS commands with `--json`
  (`shani-deploy --status`, `shani-health --verify`, `gen-efi tpm2-status`,
  `shani-etc-changes list`, `shani-upgrade-adviser`); they are the root layer.

## The layers

```
UIs (no logic)      shani-shell (QML)    GTK UIs (Cassini, Link, Backup, Chronoa-gtk)    Chronoa TUI    Chronoa skills + MCP    CLI
                          \_____ drawn from the registry ______/                      \__ generated from it __/
Capability registry  one description per capability: method, inputs/outputs, words, privilege, consent, page
Domain services      dione-<domain>: Varlink over a Unix socket, socket-activated, push events
OS commands          shani-deploy: run as root through polkit, contract-tested
```

1. **OS commands** (`shani-deploy`): root work only, behind polkit. Unchanged,
   but every caller is contract-tested against the real parser.
2. **Domain services** (new repo **`dione`**): one Python
   package per domain (`phone`, `system`, `backup`, `containers`, `network`,
   `disks`, `updates`, ...). GLib/Gio/Gst allowed, **GTK and Qt never**. Each
   domain runs as a small user service speaking **Varlink** (JSON over a Unix
   socket, what systemd itself uses): started on first use, exits when idle,
   pushes events (`more` replies) instead of being polled. The `.varlink`
   interface file is the contract; `varlinkctl` is a CLI for free. A stateful
   domain (phone lines, Bluetooth calls, watch, FM, NFC/IR) is the **only**
   owner of its hardware; everything else is its client.
3. **Capability registry** (in the same repo): each capability described once:
   the method, its inputs and outputs, privilege (user / polkit), consent key,
   plain words (translatable), and where it belongs (page, section). From it:
   the service method stubs, the CLI, generated test stand-ins, Chronoa's skill
   and MCP tool, docs, and **settings/status pages** drawn by one renderer in
   QML and one in GTK.
4. **UIs** hold no logic. Rich apps (Calls, Files, the editor, Chronoa's
   conversation) keep their own native UIs; settings and status pages are drawn
   from the registry. QML on niri, GTK on the other editions, and a **terminal
   UI for Chronoa** everywhere (the only one on the server and kiosk images):
   one more client of the engine, like the shell's panel, with no logic of its own.

## Rules (apply now, in every repo, before the new repo exists)

1. **One implementation per capability.** Never add a second copy. If logic
   exists twice, fix it in the copy named the seed below and say in the commit
   which copy still needs the change.
   - Phone/device engines: the seed is `shani-shell/bridge/phone`.
   - System reads/actions: the seed is the shell's `bridge/system_*.py` unless
     the inventory (below) says another copy is better.
2. **Logic out of UI files.** New logic goes in GTK-free, QML-free Python
   functions that return plain data (dicts/lists), never into a GTK tab, a QML
   file or a bridge's `main()`. A bridge is: parse argv, call a function, print
   JSON. In a GTK app, move logic you touch out of the widget code into such a
   module in the same repo: it moves to `dione` later as-is.
3. **Data and codes from backends, words in UIs.** A backend returns stable
   keys and codes (`"status": "warn"`, `"name": "btrfs_scrub"`); the UI owns the
   sentence. Where a backend must carry a human message, keep it short and
   translatable, never the only signal.
4. **Contract-test every call to another repo's command.** Like
   `shani-shell/tests/test_os_cli_contract.py`: every option and subcommand you
   pass must exist in the real parser (read from the sibling checkout), with a
   negative control.
5. **Stand-ins reject what the real thing rejects.** A fake that accepts any
   argument hides bugs. Fakes take the real interface (and, once it exists, are
   generated from the `.varlink` file).
6. **One owner per device.** Never import a stateful engine into a second
   process. Talk to its service.
7. **Keep history, keep shims, delete last.** Move code with history
   (`git subtree split`, as `shani-chronoa-extras` was made). Leave the old
   import path as a small shim until every consumer has switched. Delete the
   old copy only after the consumer's suite and live checks pass on the new
   path.
8. **No new dependencies** for any of this (Varlink is stdlib JSON over a
   socket; Quickshell has `Socket`).
9. Verify by execution: each repo's own harness, the testbed for real boots.
10. **The shell consumes every engine.** On niri the shell is the whole UI:
    every engine capability (OS commands, Chronoa, backup, phone, the system
    logic, the extras tools) gets a shell part (app, Settings page, panel)
    that calls the engine, never a copy of its logic and never a GTK app.
    `docs/CAPABILITY-INVENTORY.md` lists what each engine offers, what the
    shell has, and the gaps in order.

## Phases

Each phase ends green and pushable on its own.

| # | Phase | Done when |
|---|---|---|
| 0 | **Spike.** System health as one Varlink domain service: a read and an action, called from QML (Quickshell `Socket`), Python and `varlinkctl`; one settings page drawn from the registry in both QML and GTK. | All four work in the shell harness and on a testbed boot, and a call is faster than spawning a bridge. If `Socket` falls short, fall back to one long-lived bridge process per domain speaking the same JSON on stdin/stdout; the registry and everything above stay. |
| 1 | **Inventory.** One table, capability by implementation (Cassini tab / shell bridge / Chronoa skill / extras tool / Link engine), and which copy is best. Kept in `shani-shell/docs/CAPABILITY-INVENTORY.md`. Also: which Cassini tabs only repeat GNOME/Plasma's own settings and need no port. | Every capability has a chosen source. |
| 2 | **Phone domain.** The two engine copies merged file by file into `dione-phone`; one service, one bus/socket name (the old names kept as aliases for a release), one data home with a first-start move from `~/.config/shani-link` and `~/.config/shani-shell`. The shell, Link's window and Chronoa become clients. Ships a unit (fixes the never-started service). | Calls, texts and the watch work from the shell and Chronoa at once on a real boot; the old copies are shims; the landline media engine (`ua`/`media`/`video`) moved, not changed. |
| 3 | **The shell's bridges become domain services,** area by area, wrapped in place (their functions are already GTK-free). The QML keeps working through shims, then switches to the socket. | Per area: shell suite + live parts green on the service. |
| 4 | **Backup split:** `shani-backup` (command + library) and `shani-backup-gtk`. Niri drops the GTK half. | Niri image has no GTK from `shani-backup`. |
| 5 | **Chronoa without GTK:** engine package and `shani-chronoa-gtk`; skills come from the registry; the shell builds QML for the remaining Chronoa windows (`shani-chronoa/docs/HEADLESS.md`); Settings starts the engine, not the GTK app; `shani-link` becomes an optional dependency. | Niri image has no GTK from our packages. |
| 5b | **Chronoa in the terminal:** `chronoa` (TUI) in the Chronoa repo, a client of the engine interface the shell uses: streamed replies, tool calls shown with their approvals (the same consent rules), slash commands generated from the registry (`/model`, `/skills`, `/memory`, `/privacy`, ...), resume a conversation, `@file` to attach, and a non-interactive mode (`chronoa -p "..."`, `--json`) for scripts. Standard library only (ANSI + readline; a full-screen view later if needed). Works over SSH. | The same conversation can be continued from the shell's panel and the terminal; approvals work in both; slot test on the server image. |
| 6 | **Cassini on the registry:** settings/status tabs drawn from the registry where the inventory keeps them; bespoke tabs call the services. | Each tab's old logic deleted. |
| 7 | **Shared words:** each capability's words translated once; the shell's i18n tool imports them. | One translation per sentence. |

## Packaging after the split

| Today | After |
|---|---|
| `shani-chronoa` (engine + GTK) | `shani-chronoa` (engine) + `shani-chronoa-gtk` |
| `shani-link` (engines + GTK app) | engines in `dione-phone`; `shani-link` is a GTK window only |
| `shani-backup` (command + GTK) | `shani-backup` + `shani-backup-gtk` |
| shell `bridge/` | `shani-shell` depends on the `dione-*` it uses |
| — | one `dione` repo, a split PKGBUILD: `dione-{phone,system,backup,...}` |

GNOME, Plasma and COSMIC images add the `-gtk` UIs; niri does not.

## Names

Distro-neutral names for what any distribution can use, `shani-` for what is
ShaniOS's own (decided 2026-11-26):

- **`dione`** - the shared backends (this plan's domain services and capability
  registry). Python package `dione`, command `dione`, packages `dione-<domain>`.
  A ShaniOS-only domain (the `shani-deploy` / `gen-efi` wrappers) lives in it
  and reports itself unavailable where those commands are absent.
- **`chronoa`** - the assistant (today `shani-chronoa`; to be renamed).
- `shani-deploy`, `shani-install-media`, `shani-pkgbuilds`, the desktop
  profiles - ShaniOS's own, keep their names.
- D-Bus/Varlink names move to the neutral names with the interface change
  (phase 3), with the old names kept as aliases for a release.

## Open decisions (the person's)

- Whether Cassini's settings/status tabs are drawn from the registry (big
  saving) or stay hand-made GTK that only calls the services.
- Phase 0 has not been started.

## Status

Add a line when you finish a piece (date, repo, what, commit).

- 2026-11-26 shani-shell: `tests/test_os_cli_contract.py` (rule 4) and the
  `shani-deploy --yes` fix (e5a8d23).
- 2026-11-26 shani-shell: row 1 of the inventory done — Security > Encryption
  and boot consumes `gen-efi` through bridge/system_security_boot.py; secrets
  on stdin, pkexec for writes, a rejecting stand-in and a live check (fce9d4f,
  aa45f75).
- 2026-11-26 shani-chronoa-extras: split from `apps/shani-sysadmin` with
  history (rule 7); public.
- 2026-11-26 shani-shell: Backup consumes every `shani-backup` command through
  `bridge/backup.py` (backup with progress, restore, backups, btrfs snapshots,
  schedule, home snapshots), with a rejecting stand-in, an argparse contract
  test and a live part (rules 4, 5, 10; f2064d6, e204613, f67c938).
- 2026-11-26 shani-shell (phase 5): the shell consumes the headless Chronoa
  engine: contract-matched Agent.Inventory, a bounded bridge read, ten
  read-only Settings pages, and a `systemctl --user` switch with no GTK app
  (2ee10b3, fa245c4).
