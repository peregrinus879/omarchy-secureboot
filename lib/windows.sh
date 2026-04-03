#!/bin/bash
# omarchy-secureboot: Windows dual-boot detection and Limine chainload entry

readonly WINDOWS_ENTRY_MARKER="# omarchy-secureboot:windows"
readonly BOOTMGFW_REL="EFI/Microsoft/Boot/bootmgfw.efi"

# Find Windows Boot Manager on any EFI System Partition.
# Returns the partition device path (e.g., /dev/sdb1) or empty string.
find_windows_esp() {
  local dev mountpoint tmpdir="" found=""

  # Clean up temporary mount on interruption or exit
  _fwe_cleanup() {
    [[ -z "$tmpdir" ]] && return
    umount "$tmpdir" 2>/dev/null || true
    rmdir "$tmpdir" 2>/dev/null || true
    tmpdir=""
  }
  trap _fwe_cleanup EXIT

  # Check partitions typed as EFI System Partition (C12A7328-...)
  while IFS= read -r dev; do
    [[ -z "$dev" ]] && continue

    # If already mounted, check directly
    mountpoint=$(findmnt -n -o TARGET "$dev" 2>/dev/null || true)
    if [[ -n "$mountpoint" ]]; then
      if [[ -f "${mountpoint}/${BOOTMGFW_REL}" ]]; then
        trap - EXIT
        echo "$dev"
        return 0
      fi
      continue
    fi

    # Temporarily mount and check
    tmpdir=$(mktemp -d)
    if mount -t vfat -o ro "$dev" "$tmpdir" 2>/dev/null; then
      if [[ -f "${tmpdir}/${BOOTMGFW_REL}" ]]; then
        found="$dev"
      fi
      umount "$tmpdir" 2>/dev/null
    fi
    rmdir "$tmpdir" 2>/dev/null
    tmpdir=""

    [[ -n "$found" ]] && { trap - EXIT; echo "$found"; return 0; }
  done < <(lsblk -nrpo NAME,PARTTYPE 2>/dev/null \
    | grep -i "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" \
    | awk '{print $1}')

  trap - EXIT
  return 1
}

# Get the PARTUUID of a partition device.
get_partuuid() {
  blkid -s PARTUUID -o value "$1" 2>/dev/null
}

# Write the Windows entry block to limine.conf for a given PARTUUID.
write_windows_entry() {
  local partuuid="$1"
  if ! cat >> "$LIMINE_CONF" <<EOF

${WINDOWS_ENTRY_MARKER}
/Windows
    comment: Windows Boot Manager
    protocol: efi
    path: guid(${partuuid}):/${BOOTMGFW_REL}
EOF
  then
    fail "Failed to write Windows entry to ${LIMINE_CONF}"
    return 1
  fi
}

# Add a Windows chainload entry to limine.conf (interactive).
add_windows_entry() {
  header "Windows Dual-Boot"

  # Check if entry already exists
  if grep -q "$WINDOWS_ENTRY_MARKER" "$LIMINE_CONF" 2>/dev/null; then
    pass "Windows entry already in limine.conf"
    return 0
  fi

  act "Scanning EFI partitions for Windows Boot Manager..."
  local win_dev
  win_dev=$(find_windows_esp) || true

  if [[ -z "$win_dev" ]]; then
    fail "Windows Boot Manager not found on any EFI partition"
    echo
    echo -e "  ${BOLD}Troubleshooting${NC}"
    echo "    - Ensure the Windows SSD is connected and visible in BIOS"
    echo "    - Check with: lsblk -f"
    echo
    return 1
  fi

  local partuuid
  partuuid=$(get_partuuid "$win_dev") || true
  if [[ -z "$partuuid" ]]; then
    fail "Could not determine PARTUUID for ${win_dev}"
    return 1
  fi

  pass "Found Windows Boot Manager on ${win_dev}"
  act "PARTUUID: ${partuuid}"

  if ! gum confirm "Add Windows to Limine boot menu?"; then
    warn "Aborted"
    return 1
  fi

  write_windows_entry "$partuuid" || return 1
  enroll_limine_config || return 1
  mkdir -p "$STATE_DIR"
  touch "${STATE_DIR}/windows-enabled"
  pass "Windows entry added to limine.conf"
  echo
  echo -e "  ${DIM}Windows will appear in the Limine boot menu on next reboot.${NC}"
  echo
}

# Upgrade existing Windows entry to include comment if missing.
upgrade_windows_entry() {
  [[ -f "$LIMINE_CONF" ]] || return 0
  grep -q "$WINDOWS_ENTRY_MARKER" "$LIMINE_CONF" || return 0

  if grep -A5 "$WINDOWS_ENTRY_MARKER" "$LIMINE_CONF" | grep -q "protocol: efi" \
    && grep -A5 "$WINDOWS_ENTRY_MARKER" "$LIMINE_CONF" | grep -q "path: guid(" \
    && ! grep -A5 "$WINDOWS_ENTRY_MARKER" "$LIMINE_CONF" | grep -q 'image_path:'; then
    return 0
  fi

  local win_dev partuuid
  win_dev=$(find_windows_esp) || return 0
  [[ -n "$win_dev" ]] || return 0

  partuuid=$(get_partuuid "$win_dev") || return 0
  [[ -n "$partuuid" ]] || return 0

  sed -i "/${WINDOWS_ENTRY_MARKER}/,\$d" "$LIMINE_CONF"
  write_windows_entry "$partuuid"
  qact "Upgraded Windows entry for Secure Boot"
}

# Restore the Windows entry if it was wiped (e.g., by omarchy-refresh-limine).
# Non-interactive: only acts if user previously opted in via 'windows' command.
restore_windows_entry() {
  # Already present, nothing to do
  grep -q "$WINDOWS_ENTRY_MARKER" "$LIMINE_CONF" 2>/dev/null && return 0

  # Never opted in via 'omarchy-secureboot windows', skip
  [[ -f "${STATE_DIR}/windows-enabled" ]] || return 0

  local win_dev
  win_dev=$(find_windows_esp) || return 0
  [[ -z "$win_dev" ]] && return 0

  local partuuid
  partuuid=$(get_partuuid "$win_dev") || return 0
  [[ -z "$partuuid" ]] && return 0

  write_windows_entry "$partuuid" || return 1
  qact "Restored Windows entry in limine.conf"
}
