# AGENTS.md - OmaSecBoot

OmaSecBoot: sbctl signing, Limine enrollment, pacman hook, and Windows BootNext handoff for Omarchy.

Command boundary: `omasecboot` is the sole user command, and `make install` removes the obsolete `omarchy-secureboot` executable. Existing hook filenames, the library path, `/var/lib` state path, Windows marker, and Limine-hook sentinel remain deployment contracts; do not rename them without a stateful migration.

## Key Files

- `README.md` - User documentation, design philosophy, troubleshooting
- `bin/omasecboot` - Entry point and command dispatcher
- `lib/*.sh` - Modular function libraries (common, checks, discover, sign, enroll, windows, status)
- `pacman-hooks/zz-omarchy-secureboot-cleanup.hook` - Pacman hook that removes stale sbctl entries before `zz-sbctl.hook` runs
- `pacman-hooks/zzz-omarchy-secureboot.hook` - Pacman hook that runs `sign` after kernel, bootloader, or snapshot-related package updates
- `limine-hooks/zzz-omarchy-secureboot-sign` - Limine post-hook that runs `sign` after upstream Limine tools mutate boot files
- `tests/install.sh` - Staged install, upgrade, hook-target, and uninstall contract checks
- `tests/windows.sh` - Hermetic Windows firmware handoff and Quattro menu contract checks
- `omarchy/omarchy-menu.jsonc` - Quattro user-menu fragment for graceful reboot-to-Windows handoff
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

Cloned under `~/Projects/quarry/`:
- `~/Projects/quarry/omarchy/` - Omarchy source (boot chain, Limine config, install scripts)
- `~/Projects/quarry/omarchy-pkgs/` - Package builds (limine-mkinitcpio-hook, limine-snapper-sync)

## Reference Docs

Before changing Secure Boot flow, sbctl tracking behavior, Limine config semantics, pacman hook behavior, UKI handling, or Windows dual-boot logic, verify the relevant official docs first. Do not rely solely on training data.

### Secure Boot

- [Arch Wiki: Unified Extensible Firmware Interface/Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot) - Comprehensive Secure Boot guide for Arch
- [Foxboron/sbctl](https://github.com/Foxboron/sbctl) - Secure Boot key manager (README, man page, JSON output format)
- [sbctl Arch Wiki](https://wiki.archlinux.org/title/Sbctl) - Arch-specific sbctl usage

### Bootloader

- [Limine Bootloader](https://github.com/limine-bootloader/limine) - GitHub repo
- [Limine CONFIG.md](https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md) - Configuration reference (`efi`, `efi_boot_entry`, and `guid(...):/path` semantics)
- [Arch Wiki: Limine](https://wiki.archlinux.org/title/Limine) - Arch-specific Limine setup

### Omarchy

- [The Omarchy Manual](https://learn.omacom.io/2/the-omarchy-manual) - Setup guides, workflows
- [Omarchy Quattro dual boot](https://omarchy.org/manual/dual-boot-install/) - Free-space installation and `limine-scan` workflow
- [Omarchy AI](https://omarchy.org/manual/ai/) - Installed agent skills and customization model
- [Omarchy 4.0.0 release](https://github.com/basecamp/omarchy/releases/tag/v4.0.0) - Quattro feature and architecture baseline
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
- [Microsoft BitLocker FAQ](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/faq) - Suspension, recovery, and Secure Boot measurement guidance

## Technical Notes

- **Snapshot UKI naming**: limine-snapper-sync creates snapshot UKIs with filename hash suffixes such as `filename.efi_sha256_[64-hex-chars]`, `filename.efi_sha1_*`, `filename.efi_b3_*`, or `filename.efi_xxh_*`. The hash suffix is part of the filename, not a Limine `path: ...#hash` suffix.
- **Limine Secure Boot model**: `setup` and `sign` ensure `ENABLE_VERIFICATION=no` and `ENABLE_ENROLL_LIMINE_CONFIG=yes`. Current Limine packages provide `/etc/boot/hooks/pre.d/10-limine-reset-enroll` and `/etc/boot/hooks/post.d/90-limine-enroll-config`. This repo signs EFI binaries with sbctl while keeping Omarchy's current path-hash generation disabled and limine.conf checksum enrollment enabled.
- **Limine 12 compatibility**: Limine 12 can enforce BLAKE2B hashes on non-EFI loaded paths when Secure Boot and config checksum enrollment are both active. Omarchy boots UKIs via `protocol: efi`, which is exempt because firmware Secure Boot verifies EFI binaries. Limine 12 expects interface colors as `RRGGBB` values. Do not add automatic path-hash rewriting unless Omarchy moves to non-EFI loaded paths or explicitly enables that model. `status` warns proactively about non-EFI path hashes and color values instead.
- **Limine config indentation**: Limine strips leading whitespace, and limine-entry-tool/limine-snapper-sync generate indented sub-entries (`  //linux`, `     ////linux`). Entry-boundary detection in `status.sh` awk parsers must match trimmed lines, not column-0 anchors.
- **Omarchy Quattro (4.0) layout**: Omarchy ships as pacman packages (`omarchy`, `omarchy-settings`) under `/usr/share/omarchy`. Limine settings live in the `/etc/limine-entry-tool.d/{omarchy-defaults,omarchy-uki}.conf` drop-ins (including `CUSTOM_UKI_NAME="omarchy"`); `/etc/default/limine` is a read layer carrying `root=` and this repo's Secure Boot settings. Omarchy does not provision sbctl keys or expose an end-to-end Secure Boot workflow. Its required limine-entry-tool package provides scanner, enrollment, signing, and locking primitives that this repo integrates with. The `00-omarchy-update-guard.hook` blocks direct `pacman -Syu` unless `OMARCHY_UPDATE_PACMAN=1`; it sorts before `zz-*` and leaves the hook ordering invariant intact.
- **Quattro native dual boot**: Quattro supports free-space installation alongside Windows and documents `limine-scan`. limine-entry-tool 1.37.1 writes scanner entries as `protocol: efi` plus `path:`. OmaSecBoot does not replace the installation flow; it specializes the boot path with `efi_boot_entry`, persistent repair, direct BootNext commands, and Secure Boot lifecycle management. `status` identifies native-form chainloads but never removes them automatically.
- **limine-entry-tool hooks**: `/etc/boot/hooks/post.d/89-warn-missing-file-hashes` can warn on Limine 12 when Secure Boot and `ENABLE_ENROLL_LIMINE_CONFIG` are active without `ENABLE_VERIFICATION=yes`; that is this repo's deliberate model, the warning stays silent for EFI-exempt UKI builds on current versions, and the hook sorts before `zzz-omarchy-secureboot-sign`. limine-entry-tool reads sbctl state via JSON.
- **Limine lock**: `with_limine_lock` locks `/run/lock/boot-partition.lock`, the `BOOT_PARTITION_LOCK` mutex owned by limine-entry-tool and limine-snapper-sync. The path must match what those binaries embed or the serialization is a no-op.
- **EFI entry handling**: Omarchy boots UKIs via `protocol: efi`. Windows uses `protocol: efi_boot_entry`, which sets firmware BootNext and triggers a reboot so Windows boots directly from `bootmgfw.efi` without going through `limine_x64.efi`. This avoids TPM PCR drift caused by `limine-snapper-sync` re-enrolling `limine_x64.efi` on every snapshot change. Detection uses `efibootmgr -v` matching on the `bootmgfw.efi` loader path, not label. `windows setup` configures Limine, `windows bootnext` only arms firmware BootNext, and `windows reboot` arms it and reboots immediately. Windows `chkdsk`/drive-check prompts are separate from BitLocker recovery; diagnose dirty bit, interrupted Windows shutdown/update, Fast Startup/hibernation, duplicate firmware entries, or NTFS mounts rather than changing the Secure Boot path first.
- **Quattro menu integration**: `omarchy/omarchy-menu.jsonc` is a user-owned menu fragment, not a package-owned shell plugin. Its `system.windows` guard uses the unprivileged `windows available` probe. Its visible terminal action runs privileged `windows bootnext`, then returns to user context for `omarchy system reboot` so Quattro closes application windows before rebooting. Never exercise this action during automated or deployment verification.
- **Command split**: `cmd_setup()` is the full provisioning path and may regenerate Limine-managed boot state. `cmd_sign()` must stay lightweight and repair the current boot state without calling `limine-update` or rebuilding UKIs.
- **Signing-last invariant**: both `cmd_setup()` and `cmd_sign()` must always run `sign_all_efi()` as the final mutation step. Any repo-managed `limine.conf` change or Limine config re-enrollment must happen before signing so the final signed state matches the repaired boot state.
- **Tracked-file source of truth**: prefer `sbctl list-files` over direct database parsing. Use direct database access only as fallback and for cleanup/compatibility logic.
- **sbctl 0.18 compatibility**: Arch's `sbctl 0.18-2` (packaging-only rebuild of the 0.18 tag) still ignores `sign -s` for already-signed files. Snapshot UKIs can therefore be signed but untracked. `sign.sh` works around this by writing the expected `SigningEntry` directly into sbctl's file database when needed. Upstream fixed this on master (commit `ae9c8958`, issue #482) but has tagged no release after 0.18 as of 2026-08-13.
- **sbctl database preference**: when fallback database access is needed, prefer `files.db` over `files.json`.
- **Pacman hook ordering dependency**: the cleanup hook (`zz-omarchy-secureboot-cleanup.hook`) relies on filename sort order to run before sbctl's `zz-sbctl.hook`. Pacman orders PostTransaction hooks alphabetically: `zz-omarchy-secureboot-cleanup` < `zz-sbctl` < `zzz-omarchy-secureboot` (because `o` < `s`, and `zzz` > `zz`). The cleanup hook mirrors `zz-sbctl.hook`'s `Type = Path` triggers so it fires in the same transactions. Other `zz-*` hooks may sort between them; the invariant is only "before `zz-sbctl`", not "adjacent to it." If upstream sbctl ever renames its hook, `status` will flag the missing `zz-sbctl.hook` and the cleanup hook filename may need adjustment.
- **Pacman vs Limine hook scope**: package-triggered repair runs a cleanup hook (stale entry removal) before the `sign` path. Limine-originated boot drift uses `/etc/boot/hooks/post.d/zzz-omarchy-secureboot-sign`, which runs the `sign` path after upstream Limine tools finish writing boot files.
- **sbctl `-g` flag risk**: `zz-sbctl.hook` runs `sbctl sign-all -g`. The `-g` flag tells sbctl to generate/rebuild UKI bundles. With `CUSTOM_UKI_NAME="omarchy"` and limine-entry-tool building UKIs (limine-entry-tool's own `sb_sign()` is disabled), the `-g` flag should be a no-op. If it causes issues, the fallback is replacing `zz-sbctl.hook` with a custom hook that runs `sbctl sign-all` without `-g`.

## Decision Rationale

- Do not reintroduce Limine `path: ...#hash` management while Omarchy's working stack still depends on `ENABLE_VERIFICATION=no` and UKI EFI paths. For Limine 12, warn on incompatible non-EFI paths rather than mutating them automatically.
- Do not add state-path migrations unless multiple deployed installs require them. The retained hook, library, state, marker, and sentinel names preserve deployed state without migration code.
- Prefer minimal repo-owned automation over replacing Omarchy behavior. The repo fills dual-boot/Secure-Boot gaps around Quattro's native flow; it should not compete with mkinitcpio, limine-entry-tool, or limine-snapper-sync.
- Prefer the Limine post-hook for Limine-originated drift.
- Prefer `protocol: efi_boot_entry` over `protocol: efi` for Windows. The chainload protocol measures `limine_x64.efi` in TPM PCR, and `limine-snapper-sync` mutates that binary on every snapshot change, making PCR values unstable for BitLocker. The `efi_boot_entry` protocol triggers a firmware reboot, keeping `limine_x64.efi` out of the Windows boot measurement chain.
- Do not remove `sign_all_efi()` from `cmd_sign()`. `zz-sbctl.hook` only re-signs files already in sbctl's database. `sign_all_efi()` discovers new files (especially snapshot UKIs from `limine-snapper-sync`) and registers them. That is the core gap this repo fills. Most files are "already signed" (skipped); it only does work for genuinely new files.
- Do not move `ensure_limine_secure_boot_settings` to setup-only. It is a cheap safety net (a few greps, no-op when correct) that catches settings overwritten by package updates or manual edits.
- Do not remove `reenroll_limine_config_if_changed` from `cmd_sign()`. It fires only when this repo's own code changed `limine.conf` (e.g., `ensure_windows_boot_entry` restoring the Windows block). It does not duplicate `limine-snapper-sync`'s enrollment.
- Do not remove enroll + sign calls from `add_windows_boot_entry()`. It is an interactive command, not triggered by hooks. When the user modifies `limine.conf` via `windows setup`, the enrollment + signing cycle must complete in the same invocation.
- Keep `ensure_limine_secure_boot_settings` writing `/etc/default/limine` under Quattro. Upstream documents that `/etc/default/limine` overrides `/etc/limine-entry-tool.conf`, no Omarchy drop-in sets `ENABLE_VERIFICATION` or `ENABLE_ENROLL_LIMINE_CONFIG`, and the package-owned `/etc/limine-entry-tool.d/` drop-ins are Omarchy's territory; a repo drop-in there is unjustified while the current write path works and survives upgrades.
- The hooks are not redundant. `zz-omarchy-secureboot-cleanup.hook` removes stale entries so `zz-sbctl.hook` does not fail on deleted files. `zz-sbctl.hook` signs tracked files. `zzz-omarchy-secureboot.hook` discovers untracked ones after relevant package transactions. `zzz-omarchy-secureboot-sign` covers Limine-originated boot drift after `limine-update` or `limine-snapper-sync`. These are different scopes, not duplication.

## Future Enhancements

- **Remove sbctl 0.18 `save_sbctl_file_entry()` workaround**: When a tagged sbctl release containing upstream fix `ae9c8958` (issue #482) reaches Arch, `sbctl sign -s` will save already-signed files to the database. At that point, remove `save_sbctl_file_entry()` from `sign.sh` and the direct database write path. Check with `pacman -Q sbctl` and the upstream release list. As of 2026-08-13, Arch ships sbctl 0.18-2, a packaging-only rebuild of the 0.18 tag; the fix has sat unreleased on master since 2026-01-01.
- **Derive Limine `efi_boot_entry` name dynamically**: `find_windows_boot_entry()` currently strips device path info from `efibootmgr` output to extract the firmware entry label. If firmware or Windows updates ever change the label, the Limine menu entry would go stale. A future improvement could compare the `entry:` value in `limine.conf` against the current firmware label and rewrite if they differ. Not currently justified since the label has been stable across all known Windows UEFI installations.
- **Marketplace companion plugin** (deferred): omarchyplugins.com is a community marketplace (HANCORE, repo `HANCORE-linux/omarchy-plugin-marketplace`, unaffiliated with 37signals) listing Quattro-format plugins: git repo + `manifest.json` (schemaVersion 1, kinds limited to six QML shell surfaces), installed user-level via `omarchy plugin add` with no scripts and no root. This repo cannot be listed as-is (no QML entry point; the install channel cannot write `/usr/local`, `/etc/pacman.d/hooks`, or `/etc/boot/hooks`). Viable path: a separate companion plugin repo (id outside `omarchy.*`, e.g. `peregrinus.secureboot`, kinds `bar-widget` + `menu`) surfacing Secure Boot status and the reboot-to-Windows action, with `sudo omasecboot setup` documented as a manual post-install step. Precedent: elynch303/security-scan ships a manual `install.sh` and passed listing. The security baseline review-allows installers/sudo/package-manager use and auto-blocks only NOPASSWD sudoers, curl-piped-to-shell, unpinned remote execution, and /tmp-PID abuse; this repo's design uses none of those. Open: maintainer acceptance of a pacman-hook-installing setup step, and whether the discretionary "suite" listing type could carry the CLI tool alone.

## Conventions

- Bash with `set -euo pipefail`
- ShellCheck clean
- No `--` prefix on subcommands (`setup` not `--setup`)
- Output helpers: `pass()`, `fail()`, `warn()`, `act()`, `die()`
- Quiet mode via `QUIET=true` (set by `--quiet` flag)
