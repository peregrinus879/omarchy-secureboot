#!/bin/bash
# omarchy-secureboot: key creation, EFI signing, database cleanup

# Create sbctl signing keys if they do not already exist.
create_keys() {
  local installed
  installed=$(sbctl status --json 2>/dev/null | jq -r '.installed // false') || true

  if [[ "$installed" == "true" ]]; then
    qpass "Signing keys already exist"
    return 0
  fi

  if ! gum confirm "Create new sbctl signing keys?"; then
    warn "Aborted"
    return 1
  fi

  sbctl create-keys || die "Key creation failed"
  qpass "Signing keys created"
}

# Remove stale entries from sbctl's database:
#   - files no longer on disk
#   - Microsoft paths (trusted via -m enrollment flag)
#   - BOOTIA32.EFI (32-bit, irrelevant on x86_64)
clean_stale_entries() {
  local -a removable
  mapfile -t removable < <(
    list_enrolled_paths | while IFS= read -r path; do
      if [[ ! -e "$path" || "$path" == */Microsoft/* || "$path" == *BOOTIA32.EFI ]]; then
        echo "$path"
      fi
    done
  )
  [[ ${#removable[@]} -eq 0 ]] && return 0

  qact "Cleaning ${#removable[@]} stale database entries"
  local file
  for file in "${removable[@]}"; do
    if sbctl remove-file "$file" >/dev/null 2>&1; then
      qpass "${file#${ESP}/}"
    else
      warn "Could not remove: ${file#${ESP}/}"
    fi
  done
}

# Discover all EFI files and sign any that are not yet signed.
# Uses -s flag to register files in sbctl's database for zz-sbctl.hook.
sign_all_efi() {
  local -a efi_files
  mapfile -t efi_files < <(discover_efi_files)
  [[ ${#efi_files[@]} -eq 0 ]] && die "No EFI files found in ${ESP}"

  local signed=0 skipped=0 failed=0
  local file is_signed
  for file in "${efi_files[@]}"; do
    # sbctl verify exits 0 regardless of result; parse JSON for actual status
    is_signed=$(sbctl verify --json "$file" 2>/dev/null \
      | jq -r '.[0].is_signed // empty') || true
    if [[ "$is_signed" == "1" ]]; then
      qpass "${file#${ESP}/} ${DIM}already signed${NC}"
      skipped=$((skipped + 1))
    else
      local _sign_rc=0
      if [[ "$QUIET" == true ]]; then
        sbctl sign -s "$file" >/dev/null || _sign_rc=$?
      else
        sbctl sign -s "$file" || _sign_rc=$?
      fi
      if [[ $_sign_rc -eq 0 ]]; then
        qact "${file#${ESP}/} ${DIM}signed${NC}"
        signed=$((signed + 1))
      else
        warn "Failed to sign: ${file#${ESP}/}"
        failed=$((failed + 1))
      fi
    fi
  done

  if [[ "$QUIET" != true ]]; then
    echo
    if [[ $failed -gt 0 ]]; then
      warn "Signed ${signed}, skipped ${skipped}, failed ${failed}"
    else
      pass "Signed ${signed}, skipped ${skipped} (already signed)"
    fi
  elif [[ $failed -gt 0 ]]; then
    warn "Failed to sign ${failed} file(s)"
  fi

  [[ $failed -eq 0 ]]
}
