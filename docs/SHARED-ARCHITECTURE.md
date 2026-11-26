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
Domain services      <backends>-<domain>: Varlink over a Unix socket, socket-activated, push events
OS commands          shani-deploy: run as root through polkit, contract-tested
```

1. **OS commands** (`shani-deploy`): root work only, behind polkit. Unchanged,
   but every caller is contract-tested against the real parser.
2. **Domain services** (new repo **`<backends>`**): one Python
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
   module in the same repo: it moves to `<backends>` later as-is.
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
| 2 | **Phone domain.** The two engine copies merged file by file into `<backends>-phone`; one service, one bus/socket name (the old names kept as aliases for a release), one data home with a first-start move from `~/.config/shani-link` and `~/.config/shani-shell`. The shell, Link's window and Chronoa become clients. Ships a unit (fixes the never-started service). | Calls, texts and the watch work from the shell and Chronoa at once on a real boot; the old copies are shims; the landline media engine (`ua`/`media`/`video`) moved, not changed. |
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
| `shani-link` (engines + GTK app) | engines in `<backends>-phone`; `shani-link` is a GTK window only |
| `shani-backup` (command + GTK) | `shani-backup` + `shani-backup-gtk` |
| shell `bridge/` | `shani-shell` depends on the `<backends>-*` it uses |
| — | one `<backends>` repo, a split PKGBUILD: `<backends>-{phone,system,backup,...}` |
| ShaniOS specifics scattered in each project | one ShaniOS extras package: the `shani-deploy`/`gen-efi` providers and the vendor config for <backends>, `chronoa` and the shell |

GNOME, Plasma and COSMIC images add the `-gtk` UIs; niri does not.

## Names

Distro-neutral names for what any distribution can use, `shani-` for what is
ShaniOS's own (the backends' name is still open):

- **The shared backends repo: name not decided yet** (to be a plain,
  descriptive, distro-neutral name). Written `<backends>` below; packages
  `<backends>-<domain>`, command `<backends> <domain> <action>`.
- **`chrono-shell`** (Chrono Shell) - the desktop shell (today `shani-shell`;
  to be renamed), and **`chronoa`** - the Chrono Assistant (today
  `shani-chronoa`; to be renamed): one distro-neutral "Chrono" family
  (decided 2026-11-26). Nothing is released yet, so the renames carry **no
  compatibility layer**: no old command (`shani` becomes `chrono`), no old
  unit or package aliases, no data-folder migration - every caller (all in
  our own repos) changes in the same step. The `dev.shani.*` identifiers do
  not change (below).
- **ShaniOS extras** (`shani-*`): everything specific to ShaniOS, kept out of
  the neutral projects (below).
- **Identifiers stay `dev.shani.*`** (app IDs, D-Bus and Varlink names,
  GSettings-free config IDs): reverse-DNS IDs name the publisher, not the
  product, and the project owns **shani.dev** (and **shanios.com**, the
  distribution's own). Like `org.kde.*` and `org.gnome.*`, they stay the same on
  every distribution and through the Chrono rename, so no dock pin, default app
  or file association breaks. shani.dev is the projects' home (Chrono Shell,
  Chronoa, the shared backends); shanios.com is ShaniOS's.

## Structure: one repo to maintain, many parts to run and package

Agents maintain this, so one repository holds the backends and their
generated clients (one AGENTS.md, one test command, one harness; a contract
change and every caller in one commit). Inside, every domain is a separate
part with strict boundaries, and at runtime each is its own service:

```
<backends>/<domain>/
  <domain>.varlink   the contract: methods, types, privilege, consent (the one file to edit)
  service.py         the implementation: plain functions returning data
  stand_in.py        generated from the contract: the fake every test (here and in UIs) uses
  cli.py             generated: `<backends> <domain> <action> [--json]`
  qml/<Domain>.qml   generated client for the shell
  client.py          generated client for GTK apps and Chronoa
  tests/
```

- A test forbids one domain importing another's internals; domains meet only
  through contracts.
- One service per domain at runtime (socket-activated): a crash in one does not
  take the others; a stateful domain is the only owner of its device.
- The UIs (the shell, `chronoa`, the GTK apps) stay their own projects with
  their own releases for now, and never copy a contract: they use the
  generated clients, and a check fails when their pinned version falls behind.

## Upstream-ready: a neutral core, distro specifics as separate extras

So that any distribution can package and reuse the work without forking it,
the way systemd, PipeWire, NetworkManager and PackageKit are reused:

1. **One release, many packages.** Built with **meson** (what packagers know);
   every domain can be switched off (`-Dphone=disabled`) and installs into its
   own package.
2. **No distribution logic in the core: providers.** A domain whose work
   differs per distribution (updates, encryption and boot, backups, software)
   defines a provider interface; the core ships neutral providers, and a
   distribution adds its own as a plugin (like PackageKit's backends or fwupd's
   plugins), upstream, not as a patch.
3. **Distro specifics live in separate, distro-only packages.** For ShaniOS:
   the providers for `shani-deploy` and `gen-efi` ship with `shani-deploy`
   itself (ShaniOS-only - no other distribution will have these tools), and
   the vendor config for
   <backends>, `chronoa` and the shell (names, branding, default apps, image
   paths) - the pattern of `fedora-release` or `ubuntu-settings`. The neutral
   projects never name ShaniOS in code.
4. **Branding and paths are configuration** (vendor config files, build
   options), never code.
5. **Stable, versioned interfaces.** The contracts are the public API:
   additions only; a removal is deprecated for two releases first.
6. **Standard layout:** `/usr/lib`, `/usr/share`, `/etc`, systemd units,
   polkit policies, XDG dirs for user data; nothing in `/usr/local`.
7. **Licences that allow reuse:** the services and UIs GPL-3.0; the generated
   client libraries LGPL, so apps under other licences use them instead of
   copying the logic.
8. **Releases packagers can trust:** tags, signed tarballs, a changelog, CI
   building on Arch, Debian and Fedora containers.
9. **We use our own release:** `shani-pkgbuilds` builds from release tags with
   no patches; a change ShaniOS needs goes upstream first.

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
- 2026-11-26 shani-shell: gaps 3 and 17-24 of the inventory closed. Every
  ShaniOS-only tool call is a `shanios_*` function in its bridge (rule 1 and
  the packaging split): `bootinfo.py` probes sbctl/EFI/MOK and parses
  pkexec `--verify-existing` SGR rows; `system_disks.py` parses btrfs
  `fi show`/`fi df`, the never-scrubbed state and the smartd schedule;
  `system_health.py` reads `--storage-info` (honest on empty stdout) and
  ausearch with an auditd/log-state verdict; `system_net.py` reads fail2ban
  jails and banned addresses; `ups.py` stages seven bounded upsmon.conf keys
  with content on stdin and a SHA-256 expect. Settings renders all of it;
  a null update check is no longer claimed as "up to date". Rejecting
  stand-ins, contract tests and a nested-shell live part cover each flow
  (a6639f0, 9ed59a0, 6c69c03).
- 2026-11-26 shani-shell: inventory gaps 4-16; the privileged helper stages
  content over stdin behind a SHA-256 expect, re-checks with sshd/visudo/
  exportfs/testparm and rolls back, staging stays in GTK-free read bridges, and
  the four Settings pages draw rows from them (f8f9c88, 7323209).
- 2026-11-26 shani-shell: a strict stand-in backs each new OS-tool option in
  `tests/test_os_cli_contract.py`, and `dev/shell-parts/access-sharing.sh`
  drives the staged reads and writes in the nested shell.
- 2026-11-26 shani-shell (phase 2 prerequisite): the phone service ships a
  `Type=dbus` user unit, a D-Bus activation file and one launcher; the live
  Calls part proves a cold method call starts it and leaves one owner of the
  landline. The PKGBUILD must install the launcher in /usr/bin, the unit in
  /usr/lib/systemd/user and the D-Bus file in /usr/share/dbus-1/services
  (296a5d5).
- 2026-11-26 shani-shell (rule 10): the Background switches get their own app
  grouped by Phone/Watch/Music, with a Settings link instead of a second copy
  of the switch logic (18ad6fa).
- 2026-11-26 shani-shell (rule 10): FM volume, recording playback, station
  finder and bands; Backup's home-snapshot timer, disk meter, file finder,
  restore-test and stale notes; all through the seed engines and the stand-ins
  (5994020, ac62fda).
- 2026-11-26 shani-shell (rule 10): call-history message/save/delete/Clear
  all/Undo and a new-message contact picker; contacts from a paired phone,
  multi-select and the full editor; a two-column watch dashboard with sync,
  settings, notice and profile actions; no GTK app started (c61d9dd,
  e69d25c, b82f359).
