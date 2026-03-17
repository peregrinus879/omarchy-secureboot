---
name: ref-docs
description: Reference docs for the secure boot stack. Verify config syntax, flags, and behavior against official sources before making changes.
---

# Documentation Reference

When working on omarchy-secureboot, fetch the relevant official documentation before making changes. Do not rely solely on training data.

## Secure Boot

- [Arch Wiki: Unified Extensible Firmware Interface/Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot) - Comprehensive Secure Boot guide for Arch
- [Foxboron/sbctl](https://github.com/Foxboron/sbctl) - Secure Boot key manager (README, man page, JSON output format)
- [sbctl Arch Wiki](https://wiki.archlinux.org/title/Sbctl) - Arch-specific sbctl usage

## Bootloader

- [Limine Bootloader](https://github.com/limine-bootloader/limine) - GitHub repo
- [Limine CONFIG.md](https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md) - Configuration reference (chainload, `guid://` paths, `efi_chainload` protocol)
- [Arch Wiki: Limine](https://wiki.archlinux.org/title/Limine) - Arch-specific Limine setup

## Omarchy

- [The Omarchy Manual](https://learn.omacom.io/2/the-omarchy-manual) - Setup guides, workflows
- [basecamp/omarchy](https://github.com/basecamp/omarchy) - Main repo (install scripts, Limine config, boot chain)
- [omacom-io/omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs) - Package builds (limine-mkinitcpio-hook, limine-snapper-sync)

## UEFI and Boot

- [Arch Wiki: UEFI](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface) - UEFI overview, boot process, EFI variables
- [Arch Wiki: EFI system partition](https://wiki.archlinux.org/title/EFI_system_partition) - ESP layout, mounting, management
- [Arch Wiki: Unified kernel image](https://wiki.archlinux.org/title/Unified_kernel_image) - UKI creation, mkinitcpio integration

## Tools

- [jqlang/jq](https://jqlang.github.io/jq/manual/) - jq manual (JSON parsing syntax)
- [charmbracelet/gum](https://github.com/charmbracelet/gum) - Interactive shell prompts
- [Arch Wiki: Pacman hooks](https://wiki.archlinux.org/title/Pacman#Hooks) - alpm hook format, ordering, triggers

## Dual Boot

- [Arch Wiki: Dual boot with Windows](https://wiki.archlinux.org/title/Dual_boot_with_Windows) - EFI considerations, partition layout, bootloader discovery
