#!/bin/bash
# omarchy-secureboot: Windows dual-boot detection and Limine EFI entry

readonly WINDOWS_ENTRY_MARKER="# omarchy-secureboot:windows"
readonly BOOTMGFW_REL="EFI/Microsoft/Boot/bootmgfw.efi"

# Find Windows Boot Manager on any EFI System Partition.
# Returns the partition device path (e.g., /dev/sdb1) or empty string.
find_windows_esp() {
  local dev mountpoint tmpdir="" found=""

  # Clean up temporary mount on interruption or exit.
  cleanup_windows_mount() {
    [[ -z "$tmpdir" ]] && return
    umount "$tmpdir" 2>/dev/null || true
    rmdir "$tmpdir" 2>/dev/null || true
    tmpdir=""
  }
  trap cleanup_windows_mount EXIT

  # Check partitions typed as EFI System Partition (C12A7328-...)
  while IFS= read -r dev; do
    [[ -z "$dev" ]] && continue

    # If already mounted, check directly
    mountpoint=$(findmnt -n -o TARGET "$dev" 2>/dev/null || true)
    if [[ -n "$mountpoint" ]]; then
      if [[ -f "${mountpoint}/${BOOTMGFW_REL}" ]]; then
        trap - EXIT
        cleanup_windows_mount
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

    if [[ -n "$found" ]]; then
      trap - EXIT
      cleanup_windows_mount
      echo "$found"
      return 0
    fi
  done < <(lsblk -nrpo NAME,PARTTYPE 2>/dev/null \
    | grep -i "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" \
    | awk '{print $1}')

  trap - EXIT
  cleanup_windows_mount
  return 1
}

# Get the PARTUUID of a partition device.
get_partuuid() {
  blkid -s PARTUUID -o value "$1" 2>/dev/null
}

# Insert or replace the repo-managed Windows block in limine.conf.
update_windows_entry_block() {
  local partuuid="$1"
  local backup tmp

  backup=$(backup_file "$LIMINE_CONF") || {
    fail "Could not back up ${LIMINE_CONF}"
    return 1
  }

  tmp=$(mktemp "/tmp/omarchy-secureboot.limine.conf.XXXXXX") || {
    discard_file_backup "$backup"
    fail "Could not create temporary file for ${LIMINE_CONF}"
    return 1
  }

  if ! awk -v marker="$WINDOWS_ENTRY_MARKER" -v rel="$BOOTMGFW_REL" -v partuuid="$partuuid" '
    function print_block() {
      print ""
      print marker
      print "/Windows"
      print "    comment: Windows Boot Manager"
      print "    protocol: efi"
      print "    path: guid(" partuuid "):" "/" rel
      inserted = 1
    }

    BEGIN {
      in_block = 0
      inserted = 0
    }

    $0 == marker {
      if (!inserted) {
        print_block()
      }
      in_block = 1
      next
    }

    in_block {
      if ($0 == "/Windows" || $0 ~ /^[[:space:]]+/ || $0 == "") {
        next
      }
      in_block = 0
    }

    {
      print
    }

    END {
      if (!inserted) {
        print_block()
      }
    }
  ' "$LIMINE_CONF" > "$tmp"; then
    rm -f "$tmp"
    discard_file_backup "$backup"
    fail "Failed to write Windows entry to ${LIMINE_CONF}"
    return 1
  fi

  if ! cp "$tmp" "$LIMINE_CONF"; then
    restore_file_backup "$backup" "$LIMINE_CONF" || true
    rm -f "$tmp"
    discard_file_backup "$backup"
    fail "Failed to update ${LIMINE_CONF}"
    return 1
  fi

  rm -f "$tmp"
  discard_file_backup "$backup"
}

# Add a Windows EFI entry to limine.conf (interactive).
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

  update_windows_entry_block "$partuuid" || return 1
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

  update_windows_entry_block "$partuuid" || return 1
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

  update_windows_entry_block "$partuuid" || return 1
  qact "Restored Windows entry in limine.conf"
}
