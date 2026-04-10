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
- `windows.sh` - Windows ESP detection, PARTUUID-based Limine EFI entry restoration
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
- **EFI entry handling**: Omarchy boots UKIs via `protocol: efi`, and Windows is added as a Limine EFI entry. For this repo, the important Secure Boot invariants are signed EFI binaries, disabled Limine path verification, and an enrolled Limine config checksum.
- **Signing-last invariant**: `cmd_sign()` and `cmd_setup()` must always run `sign_all_efi()` as the absolute last step. All operations that modify the Limine binary (config enrollment) or `limine.conf` (Windows entry restore/upgrade) must complete before signing. Post-sign binary modifications change TPM PCR measurements without invalidating the Authenticode signature, which triggers BitLocker recovery on Windows dual-boot systems.
- **Tracked-file source of truth**: prefer `sbctl list-files` over direct database parsing. Use direct database access only as fallback and for cleanup/compatibility logic.
- **sbctl 0.18 compatibility**: Arch's `sbctl 0.18-1` still ignores `sign -s` for already-signed files. Snapshot UKIs can therefore be signed but untracked. `sign.sh` works around this by writing the expected `SigningEntry` directly into sbctl's file database when needed.
- **sbctl database preference**: when fallback database access is needed, prefer `files.db` over legacy `files.json`. Older states can still leave `files.json` behind.
- **Pacman vs non-pacman scope**: this repo owns package-triggered repair well, but does not yet ship separate automation for non-pacman snapshot rewrites. Manual `sign` remains the supported repair step there.
- **inotify-tools**: optional upstream watcher helper only. Do not treat it as a core dependency for this repo.
- **sbctl `-g` flag risk**: `zz-sbctl.hook` runs `sbctl sign-all -g`. The `-g` flag tells sbctl to generate/rebuild UKI bundles. With `CUSTOM_UKI_NAME="omarchy"` and limine-entry-tool building UKIs (limine-entry-tool disabled its own `sb_sign()` since v1.24.0-2), the `-g` flag should be a no-op. If it causes issues, the fallback is replacing `zz-sbctl.hook` with a custom hook that runs `sbctl sign-all` without `-g`.

## Decision Rationale

- Do not reintroduce Limine `path: ...#hash` management while Omarchy's working stack still depends on `ENABLE_VERIFICATION=no`.
- Do not add repo migration code unless multiple deployed installs require it. For this project, a one-user local transition did not justify permanent migration logic.
- Prefer minimal repo-owned automation over replacing Omarchy behavior. The repo fills dual-boot/Secure-Boot gaps; it should not compete with mkinitcpio, limine-entry-tool, or limine-snapper-sync.
- When a future session revisits snapshot automation, start from a repo-owned timer/service or a cleaner upstream watcher integration. Do not make `inotify-tools` a hard prerequisite without that decision.

## Conventions

- Bash with `set -euo pipefail`
- ShellCheck clean
- No `--` prefix on subcommands (`setup` not `--setup`)
- Output helpers: `pass()`, `fail()`, `warn()`, `act()`, `die()`
- Quiet mode via `QUIET=true` (set by `--quiet` flag)
