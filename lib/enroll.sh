#!/bin/bash
# omarchy-secureboot: key enrollment into UEFI firmware

enroll_keys() {
  local setup_mode
  setup_mode=$(sbctl status --json 2>/dev/null | jq -r '.setup_mode // false') || true
  [[ -z "$setup_mode" ]] && die "Could not read sbctl status"

  if [[ "$setup_mode" != "true" ]]; then
    fail "Firmware is not in Setup Mode"
    echo
    echo -e "  ${BOLD}To enter Setup Mode${NC}"
    echo "    1. Reboot into BIOS/UEFI firmware settings"
    echo "    2. Clear/reset Secure Boot keys"
    echo -e "    3. Save, reboot, run ${BOLD}sudo omarchy-secureboot enroll${NC}"
    echo
    exit 1
  fi

  pass "Firmware is in Setup Mode"

  if ! gum confirm "Enroll keys? (includes Microsoft + firmware-builtin)"; then
    warn "Aborted"
    exit 1
  fi

  # -m: include Microsoft keys (required for Windows dual-boot and Option ROMs)
  # -f: include firmware-builtin keys (safety net for vendor firmware components)
  sbctl enroll-keys -m -f || die "Key enrollment failed"
  pass "Keys enrolled"

  echo
  echo -e "  ${BOLD}Next steps${NC}"
  echo "    1. Reboot into BIOS/UEFI firmware settings"
  echo "    2. Enable Secure Boot"
  echo "    3. Save and exit"
  echo -e "    Verify after reboot: ${BOLD}sudo omarchy-secureboot status${NC}"
  echo
}
