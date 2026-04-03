#!/bin/bash
# omarchy-secureboot: key creation, EFI signing, database cleanup

readonly LIMINE_DEFAULT_CONF="/etc/default/limine"

# Set or replace a simple key="value" entry in /etc/default/limine.
# Returns 0 if the file changed, 1 if it was already correct.
set_limine_default_value() {
  local key="$1" value="$2"
  local desired="${key}=${value}"

  grep -qxF "$desired" "$LIMINE_DEFAULT_CONF" 2>/dev/null && return 1

  if grep -q "^${key}=" "$LIMINE_DEFAULT_CONF" 2>/dev/null; then
    sed -i "s|^${key}=.*|${desired}|" "$LIMINE_DEFAULT_CONF"
  else
    printf '%s\n' "$desired" >> "$LIMINE_DEFAULT_CONF"
  fi
  return 0
}

# Ensure Limine is configured for Secure Boot on Limine 11.2.0+.
# Returns 0 if settings changed, 1 if already correct or config not found.
ensure_limine_secure_boot_settings() {
  [[ -f "$LIMINE_DEFAULT_CONF" ]] || return 1

  local changed=1

  if set_limine_default_value "ENABLE_ENROLL_LIMINE_CONFIG" "yes"; then
    changed=0
  fi

  if set_limine_default_value "COMMANDS_BEFORE_SAVE" '"limine-reset-enroll"'; then
    changed=0
  fi

  if set_limine_default_value "COMMANDS_AFTER_SAVE" '"limine-enroll-config"'; then
    changed=0
  fi

  if [[ $changed -eq 0 ]]; then
    qact "Updated Limine Secure Boot settings for config enrollment"
    return 0
  fi

  qpass "Limine Secure Boot settings already configured"
  return 1
}

# Compatibility shim for older call sites.
# Returns 0 if Limine settings changed, 1 otherwise.
disable_limine_verification() {
  ensure_limine_secure_boot_settings
}

# Regenerate Limine entries after changing /etc/default/limine.
refresh_limine_config() {
  command -v limine-update >/dev/null 2>&1 || return 1
  qact "Regenerating Limine boot entries"
  limine-update || return 1

  if command -v limine-snapper-sync >/dev/null 2>&1; then
    qact "Refreshing Limine snapshot entries"
    limine-snapper-sync || return 1
  fi
}

# Enroll the current limine.conf checksum into the Limine EFI binary.
enroll_limine_config() {
  command -v limine-enroll-config >/dev/null 2>&1 || return 1
  qact "Enrolling Limine config checksum"
  limine-enroll-config || return 1
}

# Compatibility shim for older call sites.
# This repo no longer mutates Limine path hashes.
strip_limine_hashes() {
  qpass "Limine path handling left to Limine tooling"
  return 1
}

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
    list_enrolled_entries | while IFS=$'\t' read -r file output; do
      output="${output:-$file}"
      if [[ ! -e "$file" || ! -e "$output" || "$file" == */Microsoft/* || "$output" == */Microsoft/* || "$file" == *BOOTIA32.EFI || "$output" == *BOOTIA32.EFI ]]; then
        printf '%s\n' "$file"
      fi
    done | sort -u
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
