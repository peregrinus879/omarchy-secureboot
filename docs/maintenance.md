# Maintenance Ledger - OmaSecBoot

This on-demand ledger preserves reference sources, versioned compatibility findings, known limitations, removal triggers, and deferred work for OmaSecBoot.

Read this file before changing Secure Boot flow, sbctl tracking, Limine configuration semantics, pacman hooks, UKI handling, Windows dual-boot behavior, or a deferred item. Current operational policy remains in `AGENTS.md`. Re-fetch documentation-derived facts, package behavior, release status, and version gates when acting on an entry.

## Reference Repositories

Cloned under `~/Projects/quarry/`:

- `~/Projects/quarry/omarchy/` - Omarchy source (boot chain, Limine config, install scripts)
- `~/Projects/quarry/omarchy-pkgs/` - package builds (limine-mkinitcpio-hook, limine-snapper-sync)

## Reference Sources

### Secure Boot

- [Arch Wiki: Unified Extensible Firmware Interface/Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot) - comprehensive Secure Boot guide for Arch
- [Foxboron/sbctl](https://github.com/Foxboron/sbctl) - Secure Boot key manager (README, man page, JSON output format)
- [sbctl Arch Wiki](https://wiki.archlinux.org/title/Sbctl) - Arch-specific sbctl usage

### Bootloader

- [Limine Bootloader](https://github.com/limine-bootloader/limine) - upstream repository
- [Limine CONFIG.md](https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md) - configuration reference (`efi`, `efi_boot_entry`, and `guid(...):/path` semantics)
- [Arch Wiki: Limine](https://wiki.archlinux.org/title/Limine) - Arch-specific Limine setup

### Omarchy

- [The Omarchy Manual](https://learn.omacom.io/2/the-omarchy-manual) - setup guides and workflows
- [Omarchy Quattro dual boot](https://omarchy.org/manual/dual-boot-install/) - free-space installation and `limine-scan` workflow
- [Omarchy AI](https://omarchy.org/manual/ai/) - installed agent skills and customization model
- [Omarchy 4.0.0 release](https://github.com/basecamp/omarchy/releases/tag/v4.0.0) - Quattro feature and architecture baseline
- [basecamp/omarchy](https://github.com/basecamp/omarchy) - main repository (install scripts, Limine config, boot chain)
- [omacom-io/omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs) - package builds (limine-mkinitcpio-hook, limine-snapper-sync)

### UEFI and Boot

- [Arch Wiki: UEFI](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface) - UEFI overview, boot process, and EFI variables
- [Arch Wiki: EFI system partition](https://wiki.archlinux.org/title/EFI_system_partition) - ESP layout, mounting, and management
- [Arch Wiki: Unified kernel image](https://wiki.archlinux.org/title/Unified_kernel_image) - UKI creation and mkinitcpio integration

### Tools

- [jqlang/jq](https://jqlang.github.io/jq/manual/) - jq manual
- [charmbracelet/gum](https://github.com/charmbracelet/gum) - interactive shell prompts
- [Arch Wiki: Pacman hooks](https://wiki.archlinux.org/title/Pacman#Hooks) - alpm hook format, ordering, and triggers

### Dual Boot

- [Arch Wiki: Dual boot with Windows](https://wiki.archlinux.org/title/Dual_boot_with_Windows) - EFI considerations, partition layout, and bootloader discovery
- [Microsoft BitLocker FAQ](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/faq) - suspension, recovery, and Secure Boot measurement guidance

## Known Limitations

- Limine 12 can enforce BLAKE2B hashes on non-EFI loaded paths when Secure Boot and config checksum enrollment are both active. Omarchy boots UKIs through `protocol: efi`, which is exempt because firmware Secure Boot verifies EFI binaries. Limine 12 expects interface colors as `RRGGBB` values. Do not add automatic path-hash rewriting unless Omarchy moves to non-EFI loaded paths or explicitly enables that model; `status` warns about incompatible non-EFI path hashes and color values.
- Omarchy Quattro 4.0 ships as pacman packages (`omarchy`, `omarchy-settings`) under `/usr/share/omarchy`. Limine settings live in `/etc/limine-entry-tool.d/{omarchy-defaults,omarchy-uki}.conf`, including `CUSTOM_UKI_NAME="omarchy"`; `/etc/default/limine` overrides `/etc/limine-entry-tool.conf` and carries `root=` plus this repo's Secure Boot settings. No Omarchy drop-in sets `ENABLE_VERIFICATION` or `ENABLE_ENROLL_LIMINE_CONFIG`, so `/etc/default/limine` remains the repo's durable write target. Omarchy does not provision sbctl keys or expose an end-to-end Secure Boot workflow; its limine-entry-tool dependency provides scanner, enrollment, signing, and locking primitives that this repo integrates with. The `00-omarchy-update-guard.hook` blocks direct `pacman -Syu` unless `OMARCHY_UPDATE_PACMAN=1`; it sorts before `zz-*` and leaves this repo's hook-ordering invariant intact.
- Quattro supports free-space installation alongside Windows and documents `limine-scan`. limine-entry-tool 1.37.1 writes scanner entries as `protocol: efi` plus `path:`. OmaSecBoot specializes that native flow with `efi_boot_entry`, persistent repair, direct BootNext commands, and Secure Boot lifecycle management; `status` identifies native-form chainloads but never removes them automatically.
- Current Limine packages provide `/etc/boot/hooks/pre.d/10-limine-reset-enroll`, `/etc/boot/hooks/post.d/89-warn-missing-file-hashes`, and `/etc/boot/hooks/post.d/90-limine-enroll-config`. The warning hook sorts before `zzz-omarchy-secureboot-sign` and stays silent for EFI-exempt UKI builds on current versions. limine-entry-tool reads sbctl state through JSON.
- Arch's sbctl 0.18-2, a packaging-only rebuild of the 0.18 tag, ignores `sign -s` for already-signed files. Snapshot UKIs can therefore be signed but untracked. `save_sbctl_file_entry()` writes the expected `SigningEntry` directly into sbctl's file database. Upstream fixed this on master in commit `ae9c8958` (issue #482) on 2026-01-01, but no later release was tagged as of 2026-08-13. Remove the workaround only after a tagged fixed release reaches Arch; verify with `pacman -Q sbctl` and the upstream release list.
- `zz-sbctl.hook` runs `sbctl sign-all -g`; `-g` tells sbctl to generate or rebuild UKI bundles. With `CUSTOM_UKI_NAME="omarchy"` and limine-entry-tool building UKIs while its own `sb_sign()` is disabled, this should be a no-op. If it causes issues, replace `zz-sbctl.hook` with a custom hook that runs `sbctl sign-all` without `-g`.
- The cleanup hook filename must sort before sbctl's package hook. If upstream renames `zz-sbctl.hook`, `status` reports it missing and the cleanup hook filename may also need adjustment.

## Deferred Items

- Derive the Limine `efi_boot_entry` name dynamically if firmware or Windows updates make its label unstable. `find_windows_boot_entry()` currently strips device-path information from `efibootmgr` output, while the managed `entry:` value remains static until setup or repair rewrites it. Known Windows UEFI installations have kept the label stable, so this is not currently justified.
- Consider a separate marketplace companion plugin rather than listing this repository directly. omarchyplugins.com is a community marketplace (HANCORE, repository `HANCORE-linux/omarchy-plugin-marketplace`, unaffiliated with 37signals) for Quattro-format plugins: a git repository plus `manifest.json` schema version 1, with kinds limited to six QML shell surfaces. Its user-level `omarchy plugin add` channel has no scripts or root access and cannot install this repo's command and hooks. A viable companion could use an ID outside `omarchy.*`, such as `peregrinus.secureboot`, with `bar-widget` and `menu` surfaces for Secure Boot status and reboot-to-Windows, while documenting `sudo omasecboot setup` as a manual prerequisite. `elynch303/security-scan` is precedent for a listed plugin with a manual `install.sh`. The marketplace baseline review-allows installers, sudo, and package-manager use; it auto-blocks NOPASSWD sudoers, curl-piped-to-shell, unpinned remote execution, and `/tmp` PID abuse, none of which this design uses. Open questions are maintainer acceptance of the pacman-hook-installing prerequisite and whether the discretionary `suite` listing type can carry the CLI tool alone.
