# System pages: where the old system manager's tabs now live

The niri edition no longer ships the separate GTK system manager. This document
is the hand-over: every tab it had, where that job lives in the shell now, and
why. A destination is one of **existing** (the shell already did this),
**extended** (an existing shell page gained what the tab showed), **new** (a
shell page made for it), **merged** (folded into another tab's page), or
**skipped** (see the last section).

The shell's shape is the rule, not the old tab list. Pages are grouped into the
Settings sidebar a person already knows — **Personal**, **Connections**,
**Apps & AI**, **Privacy & security**, **System**. Admin and rare pages are a
short read-first page: state first, then the one or two actions the old tab
offered. Privileged writes go through `pkexec` and a polkit action the way the
shell already does them; reads stay with the user where possible.

## 1. Everyday system pages

| Old tab | Now lives in | Kind | Why |
| --- | --- | --- | --- |
| `overview.py` | **Settings › System › About**, new Overview section at the top: slot, version, channel, health at a glance | extended | About is already the machine's page; a glance belongs above its hardware facts. |
| `firmware.py` | **Settings › System › Firmware updates** (`firmware`): fwupd devices, updates offered, apply with the TPM/passphrase cost named first | new | The old Updates only listed firmware names from `shani-deploy`; devices, updates and apply need fwupd's own contract. **Updates opens this page** instead of the old app — the notification action and the Install firmware button both land here. |
| `health.py` | **Settings › System › System health** (`health`): run the checks on request, one plain-word result each | new | About had four checks read once on open; the full `shani-health` report is a page of its own. |
| `maintenance.py` | **Settings › System › Maintenance** (`maintenance`): system clean-up as root with a reason, a diagnostic report to save, factory reset behind a typed confirmation | new | The shell's Storage page cleans *your* space only. System space needs root and an explanation before the prompt. |
| `graphics.py`, `drivers.py` | **Settings › System › Graphics & drivers** (`graphics`): GPU, bound driver, driver package, render nodes, PCI devices | merged + new | The old drivers and graphics tabs ran `lspci -k` twice; one read answers both. About keeps the short summary, this page the detail. |
| `app_versions.py` | **Settings › System › App versions** (`appversions`) | new | Flatpak, snap and OS deployment versions; Software still owns updates. No total across three managers that cannot be added. |
| `etc_changes.py` | **Settings › System › System changes** (`etcchanges`): list what this computer changed in `/etc`, diff one file, queue it back for next boot | new | The overlay's upper layer is the machine's own state and root-only; restoring it is queued, never applied under a mounted overlay. |
| `persistence.py` | **Settings › System › Persistence** (`persistence`): what survives a slot switch and what only looks like it does | new | The only page that can say a service may be installed, disabled and blocked while its state still lives under `/data`. |
| `dns.py` | **Settings › Connections › DNS** (`dns`): which resolver answers, set one through the shell's existing resolved writer | new | Network already shows a connection's DNS servers; the new page reports the resolver actually in charge (`resolvectl`, `/etc/resolv.conf`, active units). |
| `kvm.py`, `virtualization.py` | **Settings › System › Virtualization** (`virtualization`): KVM readiness, then libvirt, LXC/LXD and nspawn read-only inventory, with a link to the shell's Containers window | merged + new | One read-only overview for three runtimes that share no command. Management stays in the Containers window (built on another branch); this page does not edit it. |

## 2. Already in the shell, checked and extended where the old tab did more

| Old tab | Now lives in | Kind | What was checked / added |
| --- | --- | --- | --- |
| `audio.py` | Personal › Sound | extended | Volume and EQ existed; added the PipeWire graph: devices, sinks/sources, current default, connected apps (keyed on section + heading so a camera is not filed as a microphone). |
| `backup.py` | System › Backup | extended | Snapshot list/create/delete and timers already ran through `backup.py`; added the timer/linger explanation the old tab gave. |
| `biometrics.py` | Privacy & security › Security | extended | Added fprintd devices and enrolled fingers through the daemon's own D-Bus interface; the polkit rules are already in the image. |
| `boot_recovery.py` | System › Boot & recovery | existing | `SettingsBoot` + `SystemRestore` already read the three `shani-deploy` documents, rollback and slot verification. |
| `camera.py` | Privacy & security › Privacy | extended | Camera switch existed; added the kernel's device list and a plain "no camera found" state. |
| `chronoa.py` | Apps & AI › Chronoa | existing | `SettingsChronoa` binds the same GSettings schema; no API keys are shown. |
| `containers.py` | The shell's Containers window | existing | Inventory and management already there; **not edited** (another branch owns it). The Virtualization page links to it. |
| `device.py`, `system.py` | System › About | existing | Host, OS, kernel, CPU, GPU, memory, boot time — one read of systemd's own answers. |
| `encryption.py` | Privacy & security › Security | extended | Added LUKS/TPM unlock state and the PCR/passphrase warning; writes stay with `gen-efi` through the polkit helper. |
| `firewall.py` | Privacy & security › Firewall | existing | `SettingsFirewall` + `Firewall.qml` already report zones and rules in the tools' own words. |
| `groups.py` | Privacy & security › Users & groups | extended | Group memberships that switch features on (sharing, virtualisation, serial) are read via `bridge/groups.py`; `wheel` stays with the Users page. |
| `journal.py` | System › Journal | extended | Storage policy and vacuum existed; added the boot list from `journalctl --list-boots`. Entry search stays in the Logs app. |
| `kernel.py`, `modules.py` | System › Kernel modules | extended | `SettingsModules` already reads `/proc/modules` and `/sys/module`; added kernel release and command line. |
| `printers.py` | Connections › Printers | existing | `SettingsPrinters` drives CUPS through `lpadmin` and pkexec. |
| `secureboot.py`, `sbctl.py` | Privacy & security › Security | extended | Secure Boot and kernel lockdown state, read from `sbctl`/`mokutil`/EFI variables with an honest "unknown" when none answers. |
| `security_keys.py` | Privacy & security › Security | extended | FIDO2/U2F's own user file and Yubico OTP state; no secrets, no second writer for a file the PAM module owns. |
| `services.py`, `timers.py` | The shell's Services & timers window | existing | `SysServices` + `bridge/services.py`: user units and timers with real switches. The window owns every mutation. |
| `sharing.py` (NFS), `smb.py` | Connections › Sharing | extended | NFS export drop-in existed in `SettingsSharing`; added a read-only Samba share summary so the two are never confused with Avahi's announcements. |
| `ssh_keys.py` | Privacy & security › Sign-in & access | extended | Authorized public keys are the user's own file, so the read and any edit stay unprivileged; no private key is ever asked for. |
| `storage.py`, `smart.py` | System › Storage and Disks & filesystems | extended | `SettingsStorage` and the Disks window own space and SMART; the new filesystem page adds btrfs/LVM/RAID detail. |
| `system.py`, `device.py` | System › About | existing | See above. |
| `timers.py` | Services & timers window | existing | See above. |
| `totp.py` | Apps & AI › Authenticator, plus Sign-in & access | extended | Website codes are `bridge/otp.py`'s; sign-in codes (`pam_oath`) get a read-only row so the two are not mistaken for one thing. |
| `updates.py` | System › Updates | existing | `SettingsUpdates` + `Updates.qml` already own channel, install and rollback. |
| `ups.py` | System › Power | existing | `SettingsUps` reads NUT. |
| `wireguard.py` | Connections › Network | extended | The VPN/WireGuard connection list existed; added each interface's on/off state from `wg-quick@` units, never `wg show` (its dump exposes peer keys). |
| `voice_access.py` | Personal › Accessibility | existing | Voice access switches already exist; the old tab was only a reporter of installed tools (skipped below). |
| `password_policy.py` | Privacy & security › Security | existing | `SettingsSecurity` already edits the pwquality drop-in. |
| `access.py` (passwordless sudo) | Privacy & security › Security | existing | `sudoers-set` writes the one drop-in `sudo` reads, with `visudo -c` before and after. |
| `hosts_env.py` | Privacy & security › Security | extended | Hosts editing existed; added a read-only list of `environment.d` variables and the note that a change applies to new sessions. |
| `setup.py` | Privacy & security › Users & groups | existing | First-account state is shown where accounts are managed. |

## 3. New admin and rare pages (read first, then one or two actions)

| Old tab | Now lives in | Kind | Why |
| --- | --- | --- | --- |
| `raid.py` | **Settings › System › Disks & filesystems** (`disksfs`), RAID section | new | mdadm arrays and a degraded/failed array are a silent data-loss risk; read-only state first, no second manager. |
| `lvm_state.py` | Disks & filesystems, LVM section | new | Physical volumes, volume groups and logical volumes from `pvs`/`vgs`/`lvs`, unprivileged where sysfs allows. |
| `btrfs.py`, `compression.py` | Disks & filesystems, Btrfs section | merged + new | Subvolumes, space, scrub state and compression in one filesystem view; `compsize` is its own package and is reported missing honestly. |
| `boot_entries.py` | **Settings › System › Boot & recovery** | extended | UEFI `BootOrder`/entries are the one boot target the slot pages cannot see; read-only, since only the installer creates them here. |
| `directory.py` | **Settings › Privacy & security › Sign-in & access** (`adminaccess`), Directory section | new | SSSD, slapd and nsswitch answer "who is this user and where did they come from" — reported from `shani-health`, never reconfigured here. |
| `kerberos.py` | Sign-in & access, Kerberos section | new | Realm and cache of the machine's own file; only the three settings an ordinary login needs, and only if a PAM stack actually loads the module. |
| `smartcard.py` | Sign-in & access, Smartcard section | new | pam-pkcs11's mapper and provider, read; the one narrow mapping edit the old tab allowed. |
| `privileges.py` | Sign-in & access, Privileges section | new | The system's polkit rules, not a second policy of the shell's — named plainly before any password is asked. |
| `access.py` (sudo rules detail) | Sign-in & access, Sudo section | extended | Read the same drop-in the Security page writes, so the two cannot disagree. |
| `remote_access.py` | Sign-in & access, Remote login section | new | sshd's sign-in drop-in, through the existing `remote-access-get/set` helper; never the main config. |
| `lsm.py` | Sign-in & access, Kernel security section | new | Which security modules are running, read from `/sys`; changing one means a reboot and a new command line, so no runtime switch is offered. |
| `inbound_access.py` | **Settings › Connections › Network services** (`netservices`), Inbound section | new | What could let traffic reach this machine: open ports, sshd, tunnels. All shipped defaults are off; the page says so. |
| `avahi.py` | Network services, mDNS section | new | What this machine announces and hears, read-only — publishing is the risky half. |
| `caddy.py` | Network services, Web server section | new | Which Caddyfile is in force, whether it parses, which sites it declares; the file and `caddy` CLI remain the only editors. |
| `cloudflared.py` | Network services, Tunnels section | new | Whether a tunnel is configured and what `cloudflared tunnel list` says — never a token or credential. |
| `outbound_mail.py` | **Settings › System › Background services** (`background`), Mail section | new | Whether a smart host is set or mail goes straight to the MX on port 25; read-only. |
| `ananicy.py` | Background services, Process priority section | new | Whether `ananicy-cpp` is doing anything; it needs privilege by construction, so the page cannot "apply" a priority from the desktop session. |
| `irqbalance.py` | Background services, IRQ section | new | Whether the daemon runs and where IRQs are pinned; never runs `--debug`, which changes the affinities it reports. |
| `audit.py` | Background services, Audit log section | new | `ausearch` records word for word, one row per event; no grading, no second opinion about the rules the machine already has. |
| `cron.py` | Services & timers window, plus Background services, Schedules section | extended | The user's crontab stays in the window; system-wide `/etc/crontab`, `/etc/cron.d` and the run-part directories get a read-only section here. |

## 4. Skipped tabs

| Old tab | Why skipped |
| --- | --- |
| `fleet.py` | Fleet is never in any image. There is no agent to report and no token to enrol with, so the page would be an empty promise. |
| `event_triggers.py` | Pure reporter: it lists whether `udevadm`, `journalctl` and `busctl` are installed. Nothing a person needs to act on; the tools' own output is in Journal and Logs. |
| `attachment.py` | Pure reporter: a list of installed archive tools. The shell's Archives app already tells you what it can open by offering the formats. |
| `memory_state.py` | Pure reporter: `/proc/meminfo` totals already appear in About and in the bar's system monitor. |
| `network_monitor.py` | Pure reporter: checks for `curl`, `iperf3` and `arpsnmp`; no state, no action. Network Tools owns the real job. |
| `voice_access.py` | Pure reporter of installed voice tools. The switches a person needs are already in Accessibility; Chronoa covers the assistant. |

## 5. References to the removed application

A case-insensitive grep for its name across `shani/`, `bridge/`, `bin/`, `dev/`,
`tests/`, `docs/`, `README.md`, `FEATURES.md` and `AGENTS.md` returns no matches.
The places that used to open it now open these pages:

- Updates' firmware notification and Install firmware button → Settings › System › Firmware updates.
- `bridge/otp.py` → sign-in tokens now point at Settings › Privacy & security › Sign-in & access.
- `bridge/cleanup.py` → system clean-up now points at Settings › System › Maintenance.
- `bin/shani-doctor.py`, `dev/showcase.sh`, `dev/session.sh`, `dev/harness.sh`,
  `tests/test_packaging.py`, `FEATURES.md`, `README.md` and the historical docs
  name the shell page instead of the removed application.
