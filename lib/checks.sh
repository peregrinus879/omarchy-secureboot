#!/bin/bash
# omarchy-secureboot: prerequisite validation

check_root() {
  [[ $EUID -eq 0 ]] || die "Root required. Run: ${BOLD}sudo omarchy-secureboot ${1:-}${NC}"
}

check_core_deps() {
  command -v sbctl >/dev/null 2>&1 \
    || die "sbctl not installed. Run: ${BOLD}sudo pacman -S sbctl${NC}"
  command -v jq >/dev/null 2>&1 \
    || die "jq not installed. Run: ${BOLD}sudo pacman -S jq${NC}"
}

check_deps() {
  check_core_deps
  command -v limine-update >/dev/null 2>&1 \
    || die "limine-update not installed. Install: ${BOLD}limine-mkinitcpio-hook${NC}"
  command -v limine-enroll-config >/dev/null 2>&1 \
    || die "limine-enroll-config not installed. Update: ${BOLD}limine-mkinitcpio-hook${NC}"
  command -v limine-reset-enroll >/dev/null 2>&1 \
    || die "limine-reset-enroll not installed. Update: ${BOLD}limine-mkinitcpio-hook${NC}"
  [[ -d "${ESP}/EFI" ]] \
    || die "${ESP}/EFI not found. Is the EFI partition mounted?"
}

check_efi_mode() {
  [[ -d /sys/firmware/efi ]] \
    || die "System did not boot in UEFI mode. Secure Boot requires UEFI."
}

require_gum() {
  command -v gum >/dev/null 2>&1 \
    || die "gum not installed. Run: ${BOLD}sudo pacman -S gum${NC}"
}
