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
- `sign.sh` - key creation, signing with `-s` (database registration), stale entry cleanup
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

## Conventions

- Bash with `set -euo pipefail`
- ShellCheck clean
- No `--` prefix on subcommands (`setup` not `--setup`)
- Output helpers: `pass()`, `fail()`, `warn()`, `act()`, `die()`
- Quiet mode via `QUIET=true` (set by `--quiet` flag)
