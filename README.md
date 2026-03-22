# omarchy-secureboot

**Secure Boot setup for [Omarchy](https://omarchy.com) with Windows dual-boot support.**

Creates signing keys, signs EFI files, enrolls keys into firmware, and adds Windows to the Limine boot menu. After setup, sbctl's pacman hook (`zz-sbctl.hook`) re-signs known files and a companion hook (`zzz-omarchy-secureboot.hook`) catches new ones (e.g., snapshot UKIs).

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

Done. Hooks handle re-signing automatically after every pacman transaction.

## Commands

### `setup`

Creates signing keys (or skips if they exist), disables Limine's Blake2b hash verification (incompatible with Secure Boot signing), regenerates boot entries, cleans stale sbctl database entries, discovers all EFI files on the ESP, and signs them with `-s` (registering in sbctl's database).

### `enroll`

Checks that firmware is in Setup Mode, then enrolls signing keys with:
- `-m` Microsoft keys (required for Windows dual-boot and Option ROMs)
- `-f` firmware-builtin keys (safety net for vendor components)

### `windows`

Detects Windows Boot Manager on any EFI System Partition. Temporarily mounts partitions as needed. Adds a Limine chainload entry using `guid(<PARTUUID>):/` paths so it works at UEFI boot time regardless of mount state.

### `status`

Shows Secure Boot state, hook status, Windows entry, and enrolled file verification. Works without root for basic info; requires root for file verification.

### `sign`

Re-discovers and re-signs all EFI files. Also ensures hash verification stays disabled (self-healing against package updates that may reset `/etc/default/limine`), strips any stale Blake2b hashes, and restores/upgrades the Windows entry. Used manually or by the pacman hook.

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

Files are signed with `sbctl sign -s`, which both signs the file and registers it in sbctl's database. This is critical: `zz-sbctl.hook` only re-signs files in the database.

### Pacman Hooks (Automatic Maintenance)

Two hooks work together after pacman transactions:

| Hook | Trigger | Purpose |
|---|---|---|
| `zz-sbctl.hook` (sbctl built-in) | All packages | Re-signs files already in sbctl's database |
| `zzz-omarchy-secureboot.hook` (ours) | linux*, limine*, snapper* | Discovers and signs NEW EFI files; strips stale hashes; restores Windows entry if wiped |

The `zzz-` prefix ensures our hook runs after `zz-sbctl.hook` and after limine-snapper-sync creates snapshot entries.

**Why this matters:** With Secure Boot enabled, the UEFI firmware verifies ALL EFI binaries it loads, including snapshot UKIs. An unsigned snapshot will fail to boot, not just warn.

**Why hash verification is disabled:** Signing an EFI file changes its content, which invalidates the pre-computed Blake2b hash in `limine.conf`. With hashes enabled, Limine detects the mismatch and displays a boot warning requiring manual confirmation (press Y). Disabling Limine's hash verification avoids this. It is safe because UEFI firmware signature verification, which is strictly stronger, supersedes it.

### Windows Chainload Entry

For dual-boot setups where Windows has its own EFI System Partition, the `windows` command:
1. Scans all EFI System Partitions via `lsblk`/`blkid`
2. Temporarily mounts partitions to verify `bootmgfw.efi`
3. Adds a `guid(<PARTUUID>):/` chainload entry to `limine.conf` with `comment: Windows Boot Manager` for the boot menu description

The PARTUUID path lets Limine's UEFI environment access the Windows ESP directly, without requiring it to be mounted in Linux.

If `omarchy-refresh-limine` or `limine-update` overwrites `limine.conf`, the Windows entry is lost. The pacman hook automatically restores it by re-detecting the Windows ESP and re-appending the entry. No manual intervention needed.

### After Setup

The ongoing maintenance chain:

```
Kernel update
  -> mkinitcpio builds UKI
  -> limine-entry-tool updates limine.conf (hash-free, verification disabled)
  -> zz-sbctl.hook re-signs UKI (already in database)
  -> zzz-omarchy-secureboot.hook signs new files, strips stale hashes

Snapshot creation
  -> limine-snapper-sync copies UKI to snapshot location
  -> zzz-omarchy-secureboot.hook signs new snapshot UKI, strips stale hashes

Bootloader update
  -> Limine hook copies fresh bootloader files
  -> zz-sbctl.hook re-signs bootloader files
  -> zzz-omarchy-secureboot.hook signs new files, strips stale hashes
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
sudo omarchy-secureboot sign      # Re-sign everything
```

Re-enable Secure Boot after confirming all files verify.

### Snapshot fails to boot after kernel update

Run `sudo omarchy-secureboot sign` to discover and sign new snapshot UKIs. The pacman hook should handle this automatically; if it didn't, check that the hook file exists at `/etc/pacman.d/hooks/zzz-omarchy-secureboot.hook`.

### Limine shows hash mismatch warning on boot

A package update may have re-enabled hash verification in `/etc/default/limine`. Run:

```bash
sudo omarchy-secureboot sign
```

This re-disables verification and strips stale hashes from `limine.conf`. The pacman hook does this automatically on relevant package updates.

### Windows disappeared from Limine boot menu

This happens when `omarchy-refresh-limine` or `limine-update` overwrites `limine.conf`. The pacman hook restores the entry automatically on the next relevant package update. To restore immediately:

```bash
sudo omarchy-secureboot sign
```

## Design Philosophy

This tool handles the parts of Secure Boot that nothing else automates:

- **One-time setup**: Key creation, hash verification disabled, initial signing, key enrollment, Windows chainload entry
- **Ongoing gap**: Discovering and signing new EFI files (snapshots) that `zz-sbctl.hook` misses

It deliberately delegates everything else:

- **Ongoing re-signing** of known files: `zz-sbctl.hook`
- **UKI building**: `mkinitcpio`
- **Boot entry management** in limine.conf: `limine-entry-tool`
- **Snapshot boot entries**: `limine-snapper-sync`

Don't automate what's already automated. Fill the gaps that aren't.

### Why `zz-sbctl.hook` works now

sbctl's built-in pacman hook previously failed on Omarchy because it tried to sign `/boot/{machine-id}` (a directory) as a file. Omarchy has since moved to `CUSTOM_UKI_NAME="omarchy"`, which places UKIs at `/boot/EFI/Linux/omarchy_linux.efi` instead. The directory-as-file error no longer occurs, and `zz-sbctl.hook` correctly re-signs all files registered in its database via `sbctl sign-all`.

## License

[MIT](LICENSE)

## Credits

Created by [peregrinus879](https://github.com/peregrinus879).

Developed with assistance from [Claude Code](https://claude.ai/code) by Anthropic.
