# omarchy-secureboot

Secure Boot setup tool for Omarchy (Arch Linux + Limine) with Windows dual-boot support.

## Key Files

- `README.md` - User documentation, design philosophy, troubleshooting
- `bin/omarchy-secureboot` - Entry point and command dispatcher
- `lib/*.sh` - Modular function libraries (common, checks, discover, sign, enroll, windows, status)
- `hooks/zzz-omarchy-secureboot.hook` - Pacman hook for signing new snapshot UKIs
- `Makefile` - Install/uninstall targets

## Architecture

Single dispatcher sources lib modules. Each lib file owns one concern:
- `common.sh` - constants, colors, output helpers, quiet mode
- `checks.sh` - root, deps, EFI mount, gum validation
- `discover.sh` - EFI file discovery, sbctl database queries (jq)
- `sign.sh` - key creation, signing with `-s` (database registration), stale entry cleanup, Limine verification config
- `enroll.sh` - key enrollment with `-m -f` flags
- `windows.sh` - Windows ESP detection across SSDs, PARTUUID-based Limine chainload entry
- `status.sh` - status display, hook checks, enrolled file verification

## Dependencies

sbctl, jq, gum (interactive only). Omarchy provides the rest (limine, mkinitcpio, limine-entry-tool, limine-snapper-sync).

## Reference Repos

Cloned in the sibling `../upstream/` directory:
- `../upstream/omarchy/` - Omarchy source (boot chain, Limine config, install scripts)
- `../upstream/omarchy-pkgs/` - Package builds (limine-mkinitcpio-hook, limine-snapper-sync)

## Skills

- `/ref-docs` - Official documentation for sbctl, Limine, Omarchy, and related tools

## Technical Notes

- **Snapshot UKI naming**: limine-snapper-sync creates snapshot UKIs with the pattern `filename.efi_sha256_[64-hex-chars]`. The SHA256 suffix is the content hash embedded in the filename. These do NOT match `*.efi` (the extension is mid-filename), so `discover_efi_files()` includes an explicit `*.efi_sha256_*` glob to find them.
- **Limine hash verification disabled**: `setup` sets `ENABLE_VERIFICATION=no` in `/etc/default/limine`. With Secure Boot active, UEFI firmware signature verification supersedes Limine's Blake2b hash check. Without this, signing EFI files invalidates the pre-computed hashes in limine.conf, causing a boot warning that requires pressing Y.
- **sbctl `-g` flag risk**: `zz-sbctl.hook` runs `sbctl sign-all -g`. The `-g` flag tells sbctl to generate/rebuild UKI bundles. With `CUSTOM_UKI_NAME="omarchy"` and limine-entry-tool building UKIs (limine-entry-tool disabled its own `sb_sign()` since v1.24.0-2), the `-g` flag should be a no-op. If it causes issues, the fallback is replacing `zz-sbctl.hook` with a custom hook that runs `sbctl sign-all` without `-g`.

## Conventions

- Bash with `set -euo pipefail`
- ShellCheck clean
- No `--` prefix on subcommands (`setup` not `--setup`)
- Output helpers: `pass()`, `fail()`, `warn()`, `act()`, `die()`
- Quiet mode via `QUIET=true` (set by `--quiet` flag)
