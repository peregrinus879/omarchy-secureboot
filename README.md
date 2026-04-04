# omarchy-secureboot

**Secure Boot setup for [Omarchy](https://omarchy.com) with Windows dual-boot support.**

Creates signing keys, configures Limine for Omarchy's current Secure Boot model, signs EFI files, enrolls keys into firmware, and adds Windows to the Limine boot menu. After setup, sbctl's pacman hook (`zz-sbctl.hook`) re-signs known files and a companion hook (`zzz-omarchy-secureboot.hook`) repairs package-triggered drift by refreshing Limine state and enrolling newly discovered EFI files.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Design Philosophy](#design-philosophy)
- [License](#license)
- [Credits](#credits)

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
3. After enrollment, Windows will prompt for the recovery key once. Enter it to unlock the drive. Subsequent boots work normally.

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

To uninstall: `sudo make uninstall`

## Quick Start

**Step 1** - Create keys and sign EFI files:

```bash
sudo omarchy-secureboot setup
```

**Step 2** - Reboot into BIOS/UEFI, clear Secure Boot keys (enter Setup Mode), save and exit.

**Step 3** - Enroll keys into firmware:

```bash
sudo omarchy-secureboot enroll
```

**Step 4** - Reboot into BIOS/UEFI, enable Secure Boot, save and exit.

**Step 5** *(dual-boot only)* - Add Windows to Limine boot menu:

```bash
sudo omarchy-secureboot windows
```

Done. Hooks handle package-triggered maintenance automatically after relevant pacman transactions.

## Commands

### `setup`

Creates signing keys (or skips if they exist), enforces `ENABLE_VERIFICATION=no` plus Limine config enrollment settings, regenerates boot entries, refreshes snapshot entries, cleans stale sbctl database entries, signs EFI files on the ESP, ensures they are tracked by sbctl, and enrolls the current `limine.conf` checksum into the Limine EFI binary.

### `enroll`

Checks that firmware is in Setup Mode, then enrolls signing keys with:
- `-m` Microsoft keys (required for Windows dual-boot and Option ROMs)
- `-f` firmware-builtin keys (safety net for vendor components)

### `windows`

Detects Windows Boot Manager on any EFI System Partition. Temporarily mounts partitions as needed. Adds a Limine EFI entry using `guid(<PARTUUID>):/` paths so it works at UEFI boot time regardless of mount state.

### `status`

Shows Secure Boot state, hook status, Windows entry, and enrolled file verification. Works without root for basic info; requires root for file verification.

### `sign`

Repairs Secure Boot state after updates by enforcing the Limine verification/enrollment settings in `/etc/default/limine`, regenerating boot entries, refreshing snapshot entries, re-signing EFI files, ensuring new EFI files are tracked by sbctl, restoring/upgrading the Windows entry, and re-enrolling the current `limine.conf` checksum. Used manually or by the pacman hook.

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

### Pacman Hooks (Automatic Maintenance)

Two hooks work together after pacman transactions:

| Hook | Trigger | Purpose |
|---|---|---|
| `zz-sbctl.hook` (sbctl built-in) | All packages | Re-signs files already in sbctl's database |
| `zzz-omarchy-secureboot.hook` (ours) | linux*, limine*, snapper* | Refreshes Limine config, re-enrolls its checksum, discovers/signs new EFI files, restores Windows entry if wiped |

The `zzz-` prefix ensures our hook runs after `zz-sbctl.hook` and after Limine-related tools have created or updated boot entries.

**Why this matters:** The current Omarchy stack works with three separate pieces:

- UEFI firmware verifies EFI binaries, so Omarchy UKIs, Limine EFI binaries, and the fallback loader must be signed.
- Limine config enrollment embeds the current `limine.conf` checksum into the Limine EFI binary.
- Limine path verification is intentionally disabled with `ENABLE_VERIFICATION=no`, so Limine does not require `path: ...#<blake2b>` suffixes.

**Why config enrollment is required:** Limine protects Secure Boot systems by embedding the checksum of `limine.conf` into the Limine EFI binary. Any time `limine.conf` changes, the checksum must be re-enrolled with `limine-enroll-config`.

**Why path hashes are not managed here:** Limine also supports `path: ...#<blake2b>` suffixes, but Omarchy's current working state uses `ENABLE_VERIFICATION=no` instead. Snapshot filenames such as `omarchy_linux.efi_sha256_<hex>` come from `limine-snapper-sync`; that SHA256 is part of the filename, not a Limine `path:` hash suffix.

**Why the repo does not rely only on sbctl internals:** Older sbctl states and migrations have used both `files.json` and `files.db`, while the public `sbctl list-files` CLI reflects the authoritative tracked set that hooks actually use. This repo therefore reads tracking state from the CLI first, and only falls back to the database for cleanup and compatibility logic.

### Windows EFI Entry

For dual-boot setups where Windows has its own EFI System Partition, the `windows` command:
1. Scans all EFI System Partitions via `lsblk`/`blkid`
2. Temporarily mounts partitions to verify `bootmgfw.efi`
3. Adds a `guid(<PARTUUID>):/` EFI entry to `limine.conf` with `comment: Windows Boot Manager` for the boot menu description

The PARTUUID path lets Limine's UEFI environment access the Windows ESP directly, without requiring it to be mounted in Linux.

If `omarchy-refresh-limine` or `limine-update` overwrites `limine.conf`, the Windows entry is lost. The pacman hook automatically restores the repo-managed block during relevant package transactions. Outside pacman, run `sudo omarchy-secureboot sign` to restore it immediately.

### After Setup

The package-triggered maintenance chain:

```
Kernel update
  -> mkinitcpio builds UKI
  -> limine-entry-tool updates limine.conf
  -> zz-sbctl.hook re-signs UKI (already in database)
  -> zzz-omarchy-secureboot.hook refreshes config enrollment and signs new files

Snapshot creation
  -> limine-snapper-sync copies UKI to snapshot location and rewrites snapshot entries
  -> if this happened during a pacman-triggered update, zzz-omarchy-secureboot.hook re-enrolls config and signs new snapshot UKIs
  -> if this happened outside pacman, run: sudo omarchy-secureboot sign

Bootloader update
  -> Limine hook copies fresh bootloader files
  -> zz-sbctl.hook re-signs bootloader files
  -> zzz-omarchy-secureboot.hook refreshes config enrollment and signs new files
```

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

### Windows not found by `windows` command

Ensure the Windows disk is connected and visible in BIOS. Check with `lsblk -f`. The command scans all partitions typed as EFI System Partition.

### Secure Boot enabled but system won't boot

Boot into BIOS, temporarily disable Secure Boot, boot into Linux, then:

```bash
sudo omarchy-secureboot status    # Check what's unsigned
sudo omarchy-secureboot sign      # Rebuild Limine config, re-enroll it, and re-sign EFI files
```

Re-enable Secure Boot after confirming all files verify.

### Snapshot fails to boot after kernel update

Run `sudo omarchy-secureboot sign` to discover and sign new snapshot UKIs. The pacman hook handles package-triggered updates only; non-pacman snapshot rewrites still need a manual repair pass for now.

### Limine panics about config checksum enrollment

This means Limine's Secure Boot config enrollment drifted out of sync after an update. Boot once with Secure Boot disabled, then run:

```bash
sudo omarchy-secureboot sign
```

This restores the required `/etc/default/limine` settings, refreshes Limine-managed entries, and re-enrolls the current config checksum. The pacman hook does this automatically on relevant package updates.

### `status` warns that `limine-snapper-sync.service` is not active

This warning is informational. It refers to Omarchy's upstream snapshot watcher, not this repo's core commands.

- Package-triggered repair still works through `zzz-omarchy-secureboot.hook`.
- Manual repair still works through `sudo omarchy-secureboot sign`.
- Immediate snapshot watching may require upstream watcher support such as `inotifywait`, which this repo does not require.

### `status` reports untracked snapshot UKIs

This means new EFI files exist under `/boot` but are not yet in sbctl's database. Register and sign them with:

```bash
sudo omarchy-secureboot sign
```

This is most common after snapshot activity that happened outside a pacman transaction.

If this still appears immediately after a successful `sign`, check `sudo sbctl list-files` and verify the repo version is current. This repo includes a compatibility workaround for Arch `sbctl 0.18-1`, where `sbctl sign -s` may refuse to save an already-signed file.

### Windows disappeared from Limine boot menu

This happens when `omarchy-refresh-limine` or `limine-update` overwrites `limine.conf`. The pacman hook restores the entry automatically on the next relevant package update. To restore immediately:

```bash
sudo omarchy-secureboot sign
```

## Design Philosophy

This tool handles the parts of Secure Boot that Omarchy does not fully automate for this exact dual-boot flow:

- **One-time setup**: Key creation, Limine verification/enrollment settings, initial signing, key enrollment, Windows EFI entry
- **Ongoing gap**: Re-enrolling changed Limine configs and signing new EFI files (especially snapshots) that `zz-sbctl.hook` misses

It deliberately delegates everything else:

- **Ongoing re-signing** of known files: `zz-sbctl.hook`
- **UKI building**: `mkinitcpio`
- **Boot entry management** in limine.conf: `limine-entry-tool`
- **Snapshot boot entries**: `limine-snapper-sync`

Don't automate what's already automated. Fill the gaps that aren't.

Current limitation: this repo owns pacman-triggered maintenance, but it does not yet ship separate automation for non-pacman snapshot rewrites.

### Session Notes

The current design is deliberate:

- keep Limine path verification disabled with `ENABLE_VERIFICATION=no`
- keep Limine config enrollment enabled and refreshed automatically
- treat snapshot filename SHA256 suffixes as limine-snapper-sync naming, not Limine path hashes
- trust `sbctl list-files` first for tracked-file truth
- keep direct sbctl database handling only for stale cleanup and the current `sbctl 0.18` save bug workaround
- do not make `inotify-tools` a hard dependency, because it belongs to upstream limine-snapper-sync watcher behavior, not this repo's core command set

### Why `zz-sbctl.hook` works now

sbctl's built-in pacman hook previously failed on Omarchy because it tried to sign `/boot/{machine-id}` (a directory) as a file. Omarchy has since moved to `CUSTOM_UKI_NAME="omarchy"`, which places UKIs at `/boot/EFI/Linux/omarchy_linux.efi` instead. The directory-as-file error no longer occurs, and `zz-sbctl.hook` correctly re-signs all files registered in its database via `sbctl sign-all`.

## License

[MIT](LICENSE)

## Credits

Created by [peregrinus879](https://github.com/peregrinus879).

Developed with assistance from [Claude Code](https://claude.ai/code) by Anthropic.
