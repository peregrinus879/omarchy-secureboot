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

## Skills

- `/ref-docs` - Official documentation for sbctl, Limine, Omarchy, and related tools

## Technical Notes

- **Snapshot UKI naming**: limine-snapper-sync creates snapshot UKIs with the pattern `filename.efi_sha256_[64-hex-chars]`. The SHA256 suffix is part of the filename, not a Limine `path: ...#hash` suffix.
- **Limine Secure Boot model**: `setup` and `sign` ensure `ENABLE_VERIFICATION=no`, `ENABLE_ENROLL_LIMINE_CONFIG=yes`, `COMMANDS_BEFORE_SAVE` contains `limine-reset-enroll`, and `COMMANDS_AFTER_SAVE` contains `limine-enroll-config`. This repo signs EFI binaries with sbctl while keeping Limine path verification disabled and limine.conf checksum enrollment enabled.
- **EFI entry handling**: Omarchy boots UKIs via `protocol: efi`, and Windows is added as a Limine EFI entry. For this repo, the important Secure Boot invariants are signed EFI binaries, disabled Limine path verification, and an enrolled Limine config checksum.
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
