# shani-shell: its part of the shared architecture

The plan for all repos is `../shani-shell/docs/SHARED-ARCHITECTURE.md` (https://github.com/shani8dev/shani-shell/blob/master/docs/SHARED-ARCHITECTURE.md). Read it first; its rules apply
here. This file is only this repo's part; change the plan there, not here.

**Role:** the niri UI (QML) and, today, the **seed** of the phone engines (`bridge/phone`) and of the system reads/actions (`bridge/system_*.py`).

**Do as much of this as your task allows** (never breaking a consumer), and
add a line to the plan's Status section when you finish something:

- Bridges stay thin: parse argv, call a plain function, print JSON. Put new logic in functions that return data, never in `main()` or in QML.
- `bridge/phone` is the copy to fix (the seed). Say in the commit if `shani-link/shani_link` still has the old behaviour.
- Every call to an OS command is covered by `tests/test_os_cli_contract.py`; extend it when you add one.
- Start and keep `docs/CAPABILITY-INVENTORY.md` (phase 1): capability, where it is implemented, which copy is best.
- Phase 0 (the Varlink spike) is driven from here: a QML client over Quickshell `Socket`, and one Settings page drawn from a registry description.
- Phase 2 prerequisite done: `data/systemd/shani-phone.service`,
  `data/dbus/dev.shani.Shell.Phone.service` and `bin/shani-phone` ship so the
  shell's phone service is activated on first use on installed niri systems.
  Keep one owner of the landline: once Chronoa stops depending on shani-link,
  that package is not installed on niri.
- Never add GTK, and never launch a GTK app to do something the shell should do.
- Rule 10: every engine gets a shell part that uses it. Work the gaps in `docs/CAPABILITY-INVENTORY.md` in its order (gen-efi/TPM2 first, then Chronoa's panels, Backup, the Cassini depth comparison, System tools).
- Packaged for every distribution (upstream-ready rules in the plan): the shell's core names no ShaniOS tool and no ShaniOS name.
  - Providers for each OS domain the shell shows - updates, rollback/snapshots, encryption and boot, health, reset, /etc changes, backup: the ShaniOS provider calls shani-deploy, gen-efi, shani-health, shani-reset, shani-etc-changes and shani-backup; generic providers use what any distribution has (PackageKit and fwupd for updates, systemd-cryptenroll for TPM unlock, snapper for snapshots); a page shows what its provider supports and says how this system handles the rest.
  - The system's name from /etc/os-release; branding, wallpapers and default apps from vendor config files (/usr/share/shani-shell/vendor.d/).
  - The core never names a `shani-*` tool or path; the ShaniOS provider (shipped by `shani-deploy`, ShaniOS-only) does.
  - A meson install that any packager can use; one PKGBUILD builds shani-shell (the neutral core) and shani-shell-shanios (ShaniOS's vendor config: name, branding, defaults); the ShaniOS providers ship with shani-deploy; CI installs and starts the core on Ubuntu, Fedora and Arch containers.
  - Where the fix belongs in ShaniOS's own tools, extend `../shani-deploy` (its docs/SHARED-PLAN.md lists what is allowed) rather than working around it here.
  - Measured 2026-11-26: 53 files name ShaniOS-only tools or the name (180 places: shani-deploy 79, "ShaniOS" 69); niri (15 files) is the shell's compositor and stays a normal dependency.
