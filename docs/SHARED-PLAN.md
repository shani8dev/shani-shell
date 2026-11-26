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
- Phase 2 prerequisite: the shell's phone service has no unit or D-Bus activation file; shipping one fixes calls on installed niri systems.
- Never add GTK, and never launch a GTK app to do something the shell should do.
- Rule 10: every engine gets a shell part that uses it. Work the gaps in `docs/CAPABILITY-INVENTORY.md` in its order (gen-efi/TPM2 first, then Chronoa's panels, Backup, the Cassini depth comparison, System tools).
