# Capability inventory: every engine, and the shell's surface for it

Phase 1 of `SHARED-ARCHITECTURE.md`. The rule this tracks: **the shell
consumes every engine**, and each engine capability has a shell part (app,
Settings page, panel or surface) that uses it. A row is done when the shell's
part exists and calls the engine (not a copy of its logic).

Seeded 2026-11-26 from measurements (grep of the trees, the engines' own CLIs,
`shani-chronoa/docs/HEADLESS.md` on the `chronoa-headless` branch). Depth was
not compared yet: "present" means the shell has a page or bridge for it, not
that it matches the other UI. Agents: refine a row when you work on it.

## Engines and the shell's coverage

| Engine | What it offers | The shell today | Gap |
|---|---|---|---|
| `shani-deploy` OS commands | deploy/rollback/status, health, reset, `/etc` changes, upgrade advice, `gen-efi` (TPM2 enrol/remove, recovery key, LUKS header backup, Secure Boot, pcrlock) | Updates, System health, Maintenance, Etc changes, System restore pages | **`gen-efi` not used at all**: TPM2 unlock, recovery key, LUKS header backup, Secure Boot/`sbctl`, pcrlock status have no shell page (Cassini: `tpm2_boot`, `encryption`, `secureboot`, `sbctl`) |
| `shani-backup` | `backup`, `restore`, `backups`, `open`, `snapshot create/list/delete`, `daily`, `predeploy`, `schedule`, `home list/...` | Backup panel (home snapshots, other drive, snapshots & schedule) and Settings > Backup, all through `bridge/backup.py` | done: backup with progress, restore into a chosen folder, open in Files, btrfs snapshot create/list/delete, daily backup switch and time, home snapshots with file/folder restore; no GTK app started. `daily`/`predeploy` are timer actions with no UI switch (the command has none) |
| Chronoa engine | conversation, approvals, models, skills, routines, triggers, memory, privacy/senses, setup, notices, schedule, voice, activity, runtime, diagnostics | Island, conversation panel, quick ask (bridge ops `ask`, `approve`, `write`, `findfiles`, `action`) | everything in `HEADLESS.md` § "Per window/panel" marked ENGINE READY (needs a shell bridge op + QML) or NEW op: conversations list, model picker, skills, routines, triggers, memory, privacy/senses settings, presets, setup wizard, notices, schedule, activity, files/workbench, runtime, voice; **Settings > Chronoa starts the GTK app** (`SettingsChronoa.qml`) |
| `shani-chronoa-extras` | 87 specialist tools (services/logs, network forensics, packet capture, drivers, containers/VMs, lab networks, disk internals) | none | a "System tools" app drawn from the registry (each tool: inputs as picks, result as a table), consent-gated like Chronoa |
| Phone/device engines | calls, texts, contacts, watch, FM, NFC/IR, Android over adb/Bluetooth | Calls, Messages, Contacts, Health, Devices, Media Player FM | parity + Android work in progress (`phone-native` branch); the shell's phone service is never started on installed systems (no unit) |
| Cassini (system logic inside GTK tabs) | 74 tabs | keyword trace for all but six | no trace: `backup` (the shell's own Backup module covers part), `boot_entries`, `irqbalance`, `sbctl`, `tpm2_boot`; `fleet` stays out (never in an image). The other 68 have a matching page or bridge by keyword: depth to be compared tab by tab |

## Cassini tabs: to compare in depth

`access ananicy app_versions attachment audio audit avahi biometrics
boot_recovery btrfs caddy camera chronoa cloudflared compression containers
cron device directory dns drivers encryption etc_changes event_triggers
firewall firmware graphics groups health hosts_env inbound_access journal
kerberos kernel kvm lsm lvm_state maintenance memory_state modules
network_monitor outbound_mail overview password_policy persistence printers
privileges raid remote_access secureboot security_keys services setup sharing
smart smartcard smb ssh_keys storage timers totp updates ups userspace_crypto
virtualization voice_access wireguard`

For each: the shell page that covers it, whether it does everything the tab
does, which copy of the logic is better (it becomes the seed), and whether
the tab only repeats GNOME/Plasma's own settings (then the GTK side needs no
port either).

## Order of work for the shell

1. `gen-efi`: Security > Encryption and boot (TPM2 unlock, recovery key, LUKS
   header backup, Secure Boot, pcrlock) - security-critical and missing.
2. Chronoa: Settings > Chronoa starts the engine, not the GTK app; then the
   ENGINE READY panels (conversations, models, skills, routines, triggers,
   memory, privacy/senses), then the NEW ops.
3. Backup: restore, snapshots, schedule, home snapshots in the Backup panel.
4. The Cassini depth comparison above, filling gaps page by page.
5. System tools from `shani-chronoa-extras`, drawn from the registry (after
   phase 0).
