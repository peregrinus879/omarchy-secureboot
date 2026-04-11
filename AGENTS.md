# AGENTS.md - omarchy-secureboot

Secure Boot setup tool for Omarchy (Arch Linux + Limine) with Windows dual-boot support.

## Key Files

- `README.md` - User documentation, design philosophy, troubleshooting
- `bin/omarchy-secureboot` - Entry point and command dispatcher
- `lib/*.sh` - Modular function libraries (common, checks, discover, sign, enroll, windows, status)
- `hooks/zzz-omarchy-secureboot.hook` - Pacman hook that runs `sign` after kernel, bootloader, or snapshot-related package updates
- `Makefile` - Install/uninstall targets

## Architecture

Single dispatcher sources lib modules. Each lib file owns one concern:
- `common.sh` - constants, colors, output helpers, quiet mode
- `checks.sh` - root, deps, EFI mount, gum validation
- `discover.sh` - EFI file discovery, sbctl tracked-file discovery, sbctl database fallback helpers
- `sign.sh` - key creation, signing, sbctl compatibility registration, stale entry cleanup, Limine verification/enrollment helpers
- `enroll.sh` - key enrollment with `-m -f` flags
- `windows.sh` - Windows firmware BootNext handoff and Limine `efi_boot_entry` management
- `status.sh` - status display, hook checks, Limine verification/enrollment checks, tracked vs discovered EFI verification

## Dependencies

sbctl, jq, gum (interactive only). Omarchy provides the rest (`limine-update`, `limine-enroll-config`, `limine-reset-enroll`, `limine-snapper-sync`).

## Reference Repos

Cloned under `~/projects/repos/references/`:
- `~/projects/repos/references/omarchy/` - Omarchy source (boot chain, Limine config, install scripts)
- `~/projects/repos/references/omarchy-pkgs/` - Package builds (limine-mkinitcpio-hook, limine-snapper-sync)

## Reference Docs

Before changing Secure Boot flow, sbctl tracking behavior, Limine config semantics, pacman hook behavior, UKI handling, or Windows dual-boot logic, verify the relevant official docs first. Do not rely solely on training data.

### Secure Boot

- [Arch Wiki: Unified Extensible Firmware Interface/Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot) - Comprehensive Secure Boot guide for Arch
- [Foxboron/sbctl](https://github.com/Foxboron/sbctl) - Secure Boot key manager (README, man page, JSON output format)
- [sbctl Arch Wiki](https://wiki.archlinux.org/title/Sbctl) - Arch-specific sbctl usage

### Bootloader

- [Limine Bootloader](https://github.com/limine-bootloader/limine) - GitHub repo
- [Limine CONFIG.md](https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md) - Configuration reference (chainload, `guid://` paths, `efi_chainload` protocol)
- [Arch Wiki: Limine](https://wiki.archlinux.org/title/Limine) - Arch-specific Limine setup

### Omarchy

- [The Omarchy Manual](https://learn.omacom.io/2/the-omarchy-manual) - Setup guides, workflows
- [basecamp/omarchy](https://github.com/basecamp/omarchy) - Main repo (install scripts, Limine config, boot chain)
- [omacom-io/omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs) - Package builds (limine-mkinitcpio-hook, limine-snapper-sync)

### UEFI and Boot

- [Arch Wiki: UEFI](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface) - UEFI overview, boot process, EFI variables
- [Arch Wiki: EFI system partition](https://wiki.archlinux.org/title/EFI_system_partition) - ESP layout, mounting, management
- [Arch Wiki: Unified kernel image](https://wiki.archlinux.org/title/Unified_kernel_image) - UKI creation, mkinitcpio integration

### Tools

- [jqlang/jq](https://jqlang.github.io/jq/manual/) - jq manual (JSON parsing syntax)
- [charmbracelet/gum](https://github.com/charmbracelet/gum) - Interactive shell prompts
- [Arch Wiki: Pacman hooks](https://wiki.archlinux.org/title/Pacman#Hooks) - alpm hook format, ordering, triggers

### Dual Boot

- [Arch Wiki: Dual boot with Windows](https://wiki.archlinux.org/title/Dual_boot_with_Windows) - EFI considerations, partition layout, bootloader discovery

## Technical Notes

- **Snapshot UKI naming**: limine-snapper-sync creates snapshot UKIs with the pattern `filename.efi_sha256_[64-hex-chars]`. The SHA256 suffix is part of the filename, not a Limine `path: ...#hash` suffix.
- **Limine Secure Boot model**: `setup` and `sign` ensure `ENABLE_VERIFICATION=no`, `ENABLE_ENROLL_LIMINE_CONFIG=yes`, `COMMANDS_BEFORE_SAVE` contains `limine-reset-enroll`, and `COMMANDS_AFTER_SAVE` contains `limine-enroll-config`. This repo signs EFI binaries with sbctl while keeping Limine path verification disabled and limine.conf checksum enrollment enabled.
- **EFI entry handling**: Omarchy boots UKIs via `protocol: efi`. Windows uses `protocol: efi_boot_entry`, which sets firmware BootNext and triggers a reboot so Windows boots directly from `bootmgfw.efi` without going through `limine_x64.efi`. This avoids TPM PCR drift caused by `limine-snapper-sync` re-enrolling `limine_x64.efi` on every snapshot change. Detection uses `efibootmgr -v` matching on the `bootmgfw.efi` loader path, not label. The `windows` command also provides a direct `efibootmgr -n` reboot path from Linux.
- **Command split**: `cmd_setup()` is the full provisioning path and may regenerate Limine-managed boot state. `cmd_sign()` must stay lightweight and repair the current boot state without calling `limine-update` or rebuilding UKIs.
- **Signing-last invariant**: both `cmd_setup()` and `cmd_sign()` must always run `sign_all_efi()` as the final mutation step. Any repo-managed `limine.conf` change or Limine config re-enrollment must happen before signing so the final signed state matches the repaired boot state.
- **Tracked-file source of truth**: prefer `sbctl list-files` over direct database parsing. Use direct database access only as fallback and for cleanup/compatibility logic.
- **sbctl 0.18 compatibility**: Arch's `sbctl 0.18-1` still ignores `sign -s` for already-signed files. Snapshot UKIs can therefore be signed but untracked. `sign.sh` works around this by writing the expected `SigningEntry` directly into sbctl's file database when needed.
- **sbctl database preference**: when fallback database access is needed, prefer `files.db` over legacy `files.json`. Older states can still leave `files.json` behind.
- **Pacman vs non-pacman scope**: this repo uses the same lightweight `sign` repair path for both package-triggered drift and non-pacman boot drift.
- **inotify-tools**: optional upstream watcher helper only. Do not treat it as a core dependency for this repo.
- **sbctl `-g` flag risk**: `zz-sbctl.hook` runs `sbctl sign-all -g`. The `-g` flag tells sbctl to generate/rebuild UKI bundles. With `CUSTOM_UKI_NAME="omarchy"` and limine-entry-tool building UKIs (limine-entry-tool disabled its own `sb_sign()` since v1.24.0-2), the `-g` flag should be a no-op. If it causes issues, the fallback is replacing `zz-sbctl.hook` with a custom hook that runs `sbctl sign-all` without `-g`.

## Decision Rationale

- Do not reintroduce Limine `path: ...#hash` management while Omarchy's working stack still depends on `ENABLE_VERIFICATION=no`.
- Do not add repo migration code unless multiple deployed installs require it. For this project, a one-user local transition did not justify permanent migration logic.
- Prefer minimal repo-owned automation over replacing Omarchy behavior. The repo fills dual-boot/Secure-Boot gaps; it should not compete with mkinitcpio, limine-entry-tool, or limine-snapper-sync.
- Prefer the repo-owned watcher for non-pacman drift. Do not make `inotify-tools` a hard prerequisite.
- Prefer `protocol: efi_boot_entry` over `protocol: efi` for Windows. The chainload protocol measures `limine_x64.efi` in TPM PCR, and `limine-snapper-sync` mutates that binary on every snapshot change, making PCR values unstable for BitLocker. The `efi_boot_entry` protocol triggers a firmware reboot, keeping `limine_x64.efi` out of the Windows boot measurement chain.
- Do not remove `sign_all_efi()` from `cmd_sign()`. `zz-sbctl.hook` only re-signs files already in sbctl's database. `sign_all_efi()` discovers new files (especially snapshot UKIs from `limine-snapper-sync`) and registers them. That is the core gap this repo fills. Most files are "already signed" (skipped); it only does work for genuinely new files.
- Do not move `apply_limine_secure_boot_settings` to setup-only. It is a cheap safety net (a few greps, no-op when correct) that catches settings overwritten by package updates or manual edits.
- Do not remove `reenroll_limine_config_if_changed` from `cmd_sign()`. It fires only when this repo's own code changed `limine.conf` (e.g., `ensure_windows_boot_entry` restoring the Windows block). It does not duplicate `limine-snapper-sync`'s enrollment.
- Do not remove enroll + sign calls from `add_windows_boot_entry()`. It is an interactive command, not triggered by hooks. When the user modifies `limine.conf` via the `windows` command, the enrollment + signing cycle must complete in the same invocation.
- The pacman hook is not triple-signing. `zz-sbctl.hook` signs tracked files. `zzz-omarchy-secureboot.hook` discovers untracked ones. The watcher covers non-pacman drift. These are different scopes, not duplication.

## Future Enhancements

- **Remove sbctl 0.18 `save_sbctl_file_entry()` workaround**: When Arch upgrades sbctl past 0.18-1, `sbctl sign -s` should correctly save already-signed files to the database. At that point, remove `save_sbctl_file_entry()` from `sign.sh` and the direct database write path. Check with `pacman -Q sbctl`. As of 2026-04-11, Arch ships sbctl 0.18-1.
- **Derive Limine `efi_boot_entry` name dynamically**: `find_windows_boot_entry()` currently strips device path info from `efibootmgr` output to extract the firmware entry label. If firmware or Windows updates ever change the label, the Limine menu entry would go stale. A future improvement could compare the `entry:` value in `limine.conf` against the current firmware label and rewrite if they differ. Not currently justified since the label has been stable across all known Windows UEFI installations.
- **Improve `efibootmgr`-missing error messages**: `find_windows_boot_entry()` returns 1 if `efibootmgr` is missing, which callers report as "Windows Boot Manager not found." A future improvement could distinguish between missing tool and missing firmware entry. Low priority since `add_windows_boot_entry()` already checks for `efibootmgr` explicitly, and the automated paths (`ensure_windows_boot_entry`, `reboot_to_windows`) correctly fail soft.

## Conventions

- Bash with `set -euo pipefail`
- ShellCheck clean
- No `--` prefix on subcommands (`setup` not `--setup`)
- Output helpers: `pass()`, `fail()`, `warn()`, `act()`, `die()`
- Quiet mode via `QUIET=true` (set by `--quiet` flag)
