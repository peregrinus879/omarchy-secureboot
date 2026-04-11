# omarchy-secureboot

**Secure Boot setup for [Omarchy](https://omarchy.com) with Windows dual-boot support.**

Creates signing keys, configures Limine for Omarchy's current Secure Boot model, signs EFI files, enrolls keys into firmware, and adds Windows to the Limine boot menu via firmware BootNext handoff. After setup, sbctl's pacman hook (`zz-sbctl.hook`) re-signs known files, a companion hook (`zzz-omarchy-secureboot.hook`) repairs package-triggered drift, and a repo-owned watcher repairs non-pacman boot drift.

## Why This Tool

Omarchy uses Limine as its bootloader with Unified Kernel Images (UKIs) and Snapper snapshots. That stack has Secure Boot gaps that generic tools do not cover:

- **sbctl** manages keys and signs EFI binaries, but does not handle Limine config enrollment, snapshot UKI discovery, or Windows dual-boot entries.
- **shim/MOK** is designed for the GRUB and systemd-boot chains. Limine uses direct UEFI Secure Boot verification with custom keys enrolled via sbctl.
- **systemd-boot** is not Omarchy's bootloader. This tool is specific to the Limine + UKI + Snapper stack that Omarchy ships.

This tool fills those gaps: it automates Limine config enrollment, discovers and signs snapshot UKIs, manages Windows dual-boot via firmware BootNext, and keeps everything consistent through both pacman hooks and a repo-owned watcher.

## Table of Contents

- [Why This Tool](#why-this-tool)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Recovery / Rollback](#recovery--rollback)
- [Design Philosophy](#design-philosophy)
- [License](#license)
- [Credits](#credits)

<details>
<summary>Glossary</summary>

| Term | Definition |
|------|------------|
| **ESP** | EFI System Partition. FAT32 partition used by UEFI firmware to find boot loaders. Mounted at `/boot` on Omarchy. |
| **Setup Mode** | UEFI firmware state where Secure Boot keys can be enrolled. Entered by clearing existing keys in BIOS settings. |
| **UKI** | Unified Kernel Image. Single EFI file containing kernel, initramfs, and command line. Built by `mkinitcpio` on Omarchy. |
| **BootNext** | UEFI firmware variable that overrides the boot order for one boot only. Used by `efi_boot_entry` and `efibootmgr -n` to boot Windows directly from firmware. |
| **Config enrollment** | Embedding `limine.conf`'s checksum into the Limine EFI binary so it can verify config integrity at boot. |
| **Signing** | Attaching a cryptographic signature to an EFI binary so UEFI firmware can verify it has not been tampered with. |

</details>

## Prerequisites

- **[Omarchy](https://omarchy.com)** with Limine bootloader, UKI, and btrfs/Snapper
- [sbctl](https://github.com/Foxboron/sbctl) - Secure Boot key manager
- [jq](https://jqlang.github.io/jq/) - JSON parser
- [gum](https://github.com/charmbracelet/gum) - interactive prompts (setup, enroll, windows)
- UEFI firmware with Secure Boot support
- EFI System Partition mounted at `/boot`
- For dual-boot: Windows with its own EFI System Partition

```bash
sudo pacman -S --needed sbctl jq gum
```

### Before You Begin (Dual-Boot with Windows)

If your Windows installation uses BitLocker drive encryption:

1. **Back up your BitLocker recovery key** before starting. Enrolling custom Secure Boot keys changes the firmware's Secure Boot policy, which triggers BitLocker recovery on the next Windows boot.
2. Find your recovery key at [aka.ms/myrecoverykey](https://aka.ms/myrecoverykey) (requires your Microsoft account), or check for a saved copy (USB drive, printout, Azure AD).
3. After enrollment, Windows will prompt for the recovery key once. Enter it to unlock the drive. Subsequent boots work normally because Windows boots directly from firmware via BootNext, bypassing the Limine EFI binary.

## Installation

```bash
git clone https://github.com/peregrinus879/omarchy-secureboot.git
cd omarchy-secureboot
sudo make install
```

Installs to:
- `/usr/local/bin/omarchy-secureboot`
- `/usr/local/lib/omarchy-secureboot/`
- `/etc/pacman.d/hooks/zzz-omarchy-secureboot.hook`
- `/etc/systemd/system/omarchy-secureboot-watcher.service`
- `/etc/systemd/system/omarchy-secureboot-watcher.path`

To uninstall: `sudo make uninstall`

## Quick Start

**Step 1** - Create keys and sign EFI files:

```bash
sudo omarchy-secureboot setup
```

**Step 2** - Reboot into BIOS/UEFI, clear Secure Boot keys (enter Setup Mode), save and exit.

> [!WARNING]
> **Dual-boot with BitLocker?** Have your recovery key ready before Step 3.
> Enrolling custom Secure Boot keys triggers BitLocker recovery on the next
> Windows boot. See [Before You Begin](#before-you-begin-dual-boot-with-windows).

**Step 3** - Enroll keys into firmware:

```bash
sudo omarchy-secureboot enroll
```

**Step 4** - Reboot into BIOS/UEFI, enable Secure Boot, save and exit.

**Step 5** *(dual-boot only)* - Add Windows to Limine boot menu:

```bash
sudo omarchy-secureboot windows
```

The first run adds Windows to the Limine menu using the `efi_boot_entry` protocol (firmware BootNext). Subsequent runs set BootNext and reboot to Windows immediately. You can also select Windows from the Limine boot menu directly. The pacman hook handles package-triggered maintenance, and the watcher handles non-pacman boot drift automatically.

## Commands

### `setup`

Creates signing keys (or skips if they exist), enforces `ENABLE_VERIFICATION=no` plus Limine config enrollment settings, regenerates boot entries, refreshes snapshot entries, ensures the Windows boot entry uses the `efi_boot_entry` protocol, re-enrolls the `limine.conf` checksum if the config changed, cleans stale sbctl database entries, and signs all EFI files on the ESP.

### `enroll`

Checks that firmware is in Setup Mode, then enrolls signing keys with:
- `-m` Microsoft keys (required for Windows dual-boot and Option ROMs)
- `-f` firmware-builtin keys (safety net for vendor components)

### `windows`

First run: detects the Windows Boot Manager in firmware boot entries (by `bootmgfw.efi` loader path), adds a Limine menu entry using the `efi_boot_entry` protocol, enrolls the config checksum, and signs EFI files. Does not reboot. Subsequent runs: sets the firmware BootNext variable to the Windows Boot Manager entry and reboots immediately. You can also select Windows from the Limine boot menu directly; it triggers the same firmware BootNext handoff. Requires `efibootmgr`.

### `status`

Shows Secure Boot state, hook status, Windows entry, and enrolled file verification. Works without root for basic info; requires root for file verification.

### `sign`

Repairs Linux-side Secure Boot state after updates by enforcing the Limine verification/enrollment settings in `/etc/default/limine`, ensuring the Windows boot entry uses the `efi_boot_entry` protocol, re-enrolling the `limine.conf` checksum if the config changed, cleaning stale database entries, and signing all EFI files currently present on the ESP. Used manually, by the pacman hook, and by the repo watcher.

### `help`

Prints usage and the five-step workflow.

### `version`

Prints the version number.

## How It Works

### EFI File Discovery

Finds all `.efi`/`.EFI` files under `/boot`, plus snapshot UKIs matching `*.efi_sha256_*` (created by limine-snapper-sync with a content hash in the filename). Excludes:

| Pattern | Reason |
|---|---|
| `*/Microsoft/*` | Signed by Microsoft; trusted via `-m` enrollment flag |
| `BOOTIA32.EFI` | 32-bit bootloader; irrelevant on x86_64 |
| `*.bak` | Backup files; not loaded by firmware |

### Signing and Database Registration

This repo treats **signature state** and **tracking state** as separate concerns:

- A file can be correctly signed but still missing from sbctl's tracked-file database.
- `zz-sbctl.hook` only re-signs files that are tracked by sbctl.

For normal unsigned files, `sbctl sign -s` both signs and tracks the file.

For already-signed files, current Arch `sbctl 0.18-1` still has an upstream compatibility bug where `--save` may be ignored. Snapshot UKIs can hit exactly that case, because limine-snapper-sync may copy already-signed EFI files into snapshot history. When that happens, this repo writes the expected sbctl file entry directly so the file becomes truly tracked and future `zz-sbctl.hook` runs include it.

This is why `sign` may report a snapshot UKI as `registered` instead of `signed`.

Tracking reads use `sbctl list-files` first, then fall back to the on-disk sbctl file database only when needed. If a fallback is required, this repo prefers `files.db` over legacy `files.json`.

### Automatic Maintenance

Package-triggered and non-pacman repair share the same lightweight `sign` path:

| Trigger | Scope | Purpose |
|---|---|---|
| `zz-sbctl.hook` (sbctl built-in) | All pacman transactions | Re-signs files already in sbctl's database |
| `zzz-omarchy-secureboot.hook` (ours) | `linux*`, `limine*`, `snapper*` packages | Runs lightweight repo repair after relevant package updates |
| `omarchy-secureboot-watcher.path` (ours) | `/boot/limine.conf` and core EFI paths | Runs the same lightweight repair after non-pacman boot drift |

The `zzz-` prefix ensures our hook runs after `zz-sbctl.hook` and after Limine-related tools have created or updated boot entries.

Our hook triggers on packages matching `linux*`, `limine*`, or `snapper*`. Other package updates do not trigger it. `zz-sbctl.hook` triggers on all packages, so already-tracked files get re-signed on any pacman transaction. Outside pacman, the repo watcher covers the same repair path.

**Why this matters:** The current Omarchy stack works with three separate pieces:

- UEFI firmware verifies EFI binaries, so Omarchy UKIs, Limine EFI binaries, and the fallback loader must be signed.
- Limine config enrollment embeds the current `limine.conf` checksum into the Limine EFI binary.
- Limine path verification is intentionally disabled with `ENABLE_VERIFICATION=no`, so Limine does not require `path: ...#<blake2b>` suffixes.

**Why config enrollment is required:** Limine protects Secure Boot systems by embedding the checksum of `limine.conf` into the Limine EFI binary. Any time `limine.conf` changes, the checksum must be re-enrolled with `limine-enroll-config`. This enrollment mutates `limine_x64.efi`, which is why Windows must boot via firmware BootNext (not chainload) to avoid TPM PCR measurement drift.

**Why path hashes are not managed here:** Limine also supports `path: ...#<blake2b>` suffixes, but Omarchy's current working state uses `ENABLE_VERIFICATION=no` instead. Snapshot filenames such as `omarchy_linux.efi_sha256_<hex>` come from `limine-snapper-sync`; that SHA256 is part of the filename, not a Limine `path:` hash suffix.

**Why the repo does not rely only on sbctl internals:** Older sbctl states and migrations have used both `files.json` and `files.db`, while the public `sbctl list-files` CLI reflects the authoritative tracked set that hooks actually use. This repo therefore reads tracking state from the CLI first, and only falls back to the database for cleanup and compatibility logic.

### Windows Boot Path

For dual-boot setups, this repo uses Limine's `efi_boot_entry` protocol instead of `efi` chainloading. When you select Windows from the Limine menu, Limine sets the firmware BootNext variable and triggers a reboot. On that reboot, firmware loads `bootmgfw.efi` directly from the Windows ESP, bypassing `limine_x64.efi` entirely.

This avoids BitLocker recovery caused by TPM PCR measurement drift. `limine-snapper-sync` re-enrolls `limine_x64.efi` on every snapshot change, mutating the binary. With chainloading (`protocol: efi`), Windows boot measurements included that binary, triggering BitLocker. With `efi_boot_entry`, TPM PCRs reset on the firmware reboot, and Windows measurements only include `bootmgfw.efi` (stable).

The `windows` command also provides a direct reboot-to-Windows path from Linux via `efibootmgr -n` (same firmware handoff, skips the Limine menu).

If `omarchy-refresh-limine` or `limine-update` overwrites `limine.conf`, the Windows entry is lost. The pacman hook and repo watcher restore it automatically with the correct `efi_boot_entry` protocol. Any legacy `protocol: efi` entries are upgraded automatically by `sign`.

### After Setup

The package-triggered maintenance chain:

```
Kernel update
  -> mkinitcpio builds UKI
  -> limine-entry-tool updates limine.conf
  -> zz-sbctl.hook re-signs UKI (already in database)
  -> zzz-omarchy-secureboot.hook ensures Windows boot entry and signs new files

Snapshot creation or cleanup
  -> limine-snapper-sync copies UKIs to snapshot locations and rewrites snapshot entries
  -> limine-snapper-sync re-enrolls and re-signs limine_x64.efi (Omarchy pipeline)
  -> repo watcher discovers and signs new snapshot UKIs

Bootloader update
  -> Limine hook copies fresh bootloader files
  -> zz-sbctl.hook re-signs bootloader files
  -> zzz-omarchy-secureboot.hook ensures Windows boot entry and signs new files
```

### Code Structure

Single dispatcher (`bin/omarchy-secureboot`) sources modular libraries:

- `common.sh` -- output helpers, quiet mode, backup/restore
- `checks.sh` -- prerequisite validation (root, deps, EFI mount)
- `discover.sh` -- EFI file discovery and sbctl database queries
- `sign.sh` -- key creation, signing, Limine config management
- `enroll.sh` -- firmware key enrollment
- `windows.sh` -- Windows firmware BootNext handoff and Limine `efi_boot_entry` management
- `status.sh` -- status display and file verification

## Troubleshooting

### Key creation or enrollment fails

sbctl stores keys in `/usr/share/secureboot/keys/` (older versions) or `/var/lib/sbctl/keys/` (newer versions). Check both locations if troubleshooting key issues:

```bash
ls /usr/share/secureboot/keys/db/db.key 2>/dev/null || ls /var/lib/sbctl/keys/db/db.key
```

### `enroll` says firmware is not in Setup Mode

Clear/reset the Secure Boot keys in your BIOS first. The exact menu location varies by manufacturer. Look under Security, Boot, or Authentication for "Clear Secure Boot keys", "Reset to Setup Mode", or similar.

### `sbctl verify` shows Microsoft files as unsigned

Normal. Microsoft files are signed with Microsoft's own keys, not yours. The firmware trusts them because you enrolled Microsoft's keys with the `-m` flag.

### Windows not found during `windows` setup

Ensure the Windows disk is connected and visible in BIOS. Check with `efibootmgr -v`. The command looks for a boot entry whose loader path contains `bootmgfw.efi`.

### Secure Boot enabled but system won't boot

Boot into BIOS, temporarily disable Secure Boot, boot into Linux, then:

```bash
sudo omarchy-secureboot status    # Check what's unsigned
sudo omarchy-secureboot sign      # Re-enroll config if needed and re-sign EFI files
```

Re-enable Secure Boot after confirming all files verify.

### Snapshot fails to boot after kernel update

Run `sudo omarchy-secureboot sign` to discover and sign new snapshot UKIs if you need an immediate manual repair. The pacman hook and watcher normally cover package-triggered and non-pacman drift automatically.

### Limine panics about config checksum enrollment

This means Limine's Secure Boot config enrollment drifted out of sync after an update. Boot once with Secure Boot disabled, then run:

```bash
sudo omarchy-secureboot sign
```

This restores the required `/etc/default/limine` settings, repairs repo-managed config drift, and re-enrolls the current config checksum. The pacman hook and watcher do this automatically in normal operation.

### `status` warns that `limine-snapper-sync.service` is not active

This warning is informational. It refers to Omarchy's upstream snapshot watcher, not this repo's core commands.

- Package-triggered repair still works through `zzz-omarchy-secureboot.hook`.
- Repo watcher coverage still works through `omarchy-secureboot-watcher.path`.
- Manual repair still works through `sudo omarchy-secureboot sign`.

### `status` reports untracked snapshot UKIs

This means new EFI files exist under `/boot` but are not yet in sbctl's database. Register and sign them with:

```bash
sudo omarchy-secureboot sign
```

This is most common after snapshot activity that happened before the watcher repaired the new files, or after boot drift introduced multiple changes at once.

If this still appears immediately after a successful `sign`, check `sudo sbctl list-files` and verify the repo version is current. This repo includes a compatibility workaround for Arch `sbctl 0.18-1`, where `sbctl sign -s` may refuse to save an already-signed file.

### Windows disappeared from Limine boot menu

This happens when `omarchy-refresh-limine` or `limine-update` overwrites `limine.conf`. The pacman hook and watcher restore the entry automatically with the correct `efi_boot_entry` protocol. To restore immediately:

```bash
sudo omarchy-secureboot sign
```

### `status` warns about legacy Windows chainload entry

Run `sudo omarchy-secureboot sign` to upgrade the entry from `protocol: efi` to `protocol: efi_boot_entry`. The upgraded entry uses firmware BootNext, which avoids BitLocker recovery by keeping `limine_x64.efi` out of the Windows boot measurement chain.

### `windows` says Windows Boot Manager not found

Ensure the Windows disk is connected and visible in BIOS. Check with `efibootmgr -v`. The command looks for a boot entry whose loader path contains `bootmgfw.efi`.

## Recovery / Rollback

### Emergency boot recovery

If the system will not boot with Secure Boot enabled:

1. Enter BIOS/UEFI firmware settings
2. Disable Secure Boot temporarily
3. Boot into Linux normally
4. Diagnose with `sudo omarchy-secureboot status`
5. Repair with `sudo omarchy-secureboot sign`
6. Re-enable Secure Boot in BIOS after confirming all files verify

### Full rollback

To remove Secure Boot entirely and return to an unsigned boot state:

1. Disable Secure Boot in BIOS/UEFI firmware settings
2. Optionally reset Secure Boot keys to factory defaults (re-enrolls Microsoft-only keys)
3. Run `sudo make uninstall` from the repo to remove the tool and pacman hook

Existing EFI signatures are harmless with Secure Boot disabled. No need to re-sign or strip signatures.

### Re-enrollment after key reset

If BIOS keys are cleared (factory reset, accidental clear, or hardware change):

1. The local signing keys from `sbctl create-keys` are still on disk. No need to recreate them.
2. Enter Setup Mode in BIOS (clear/reset Secure Boot keys)
3. Run `sudo omarchy-secureboot enroll` to re-enroll your keys
4. Enable Secure Boot in BIOS

If you need to verify your keys still exist: `sbctl status`

## Design Philosophy

This tool handles the parts of Secure Boot that Omarchy does not fully automate for this exact dual-boot flow:

- **One-time setup**: Key creation, Limine verification/enrollment settings, initial signing, key enrollment, Windows boot entry via `efi_boot_entry` protocol
- **Ongoing repair**: Re-enrolling changed Limine configs, signing new EFI files (especially snapshots), and restoring the Windows boot entry. Windows boots via firmware BootNext for TPM/BitLocker compatibility

It deliberately delegates everything else:

- **Ongoing re-signing** of known files: `zz-sbctl.hook`
- **UKI building**: `mkinitcpio`
- **Boot entry management** in limine.conf: `limine-entry-tool`
- **Snapshot boot entries**: `limine-snapper-sync`

Don't automate what's already automated. Fill the gaps that aren't.

Current design: this repo owns both pacman-triggered maintenance and non-pacman boot-drift repair.

### Session Notes

The current design is deliberate:

- keep Limine path verification disabled with `ENABLE_VERIFICATION=no`
- keep Limine config enrollment enabled and refreshed automatically
- use `protocol: efi_boot_entry` (firmware BootNext) for Windows, not `protocol: efi` (chainload), to avoid TPM PCR drift from `limine-snapper-sync` enrollment
- treat snapshot filename SHA256 suffixes as limine-snapper-sync naming, not Limine path hashes
- trust `sbctl list-files` first for tracked-file truth
- keep direct sbctl database handling only for stale cleanup and the current `sbctl 0.18` save bug workaround
- keep `sign` lightweight so automation repairs the current boot state instead of rebuilding it
- do not make `inotify-tools` a hard dependency, because it belongs to upstream limine-snapper-sync watcher behavior, not this repo's core command set

### Why `zz-sbctl.hook` works now

sbctl's built-in pacman hook previously failed on Omarchy because it tried to sign `/boot/{machine-id}` (a directory) as a file. Omarchy has since moved to `CUSTOM_UKI_NAME="omarchy"`, which places UKIs at `/boot/EFI/Linux/omarchy_linux.efi` instead. The directory-as-file error no longer occurs, and `zz-sbctl.hook` correctly re-signs all files registered in its database via `sbctl sign-all`.

## License

[MIT](LICENSE)

## Credits

Created by [peregrinus879](https://github.com/peregrinus879).
