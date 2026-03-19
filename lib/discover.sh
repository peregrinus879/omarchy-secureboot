#!/bin/bash
# omarchy-secureboot: EFI file discovery and sbctl database queries

# Find all signable EFI files under the ESP.
# Excludes Microsoft files (trusted via -m enrollment), 32-bit bootloader, backups.
discover_efi_files() {
  find "${ESP}" -type f \( -name "*.efi" -o -name "*.EFI" -o -name "*.efi_sha256_*" \) \
    ! -path "*/Microsoft/*" \
    ! -name "BOOTIA32.EFI" \
    ! -name "*.bak" \
    2>/dev/null | sort
}

# List file paths currently registered in sbctl's database.
list_enrolled_paths() {
  local json
  json=$(sbctl list-files --json 2>/dev/null) || return 0

  if [[ "$json" == "null" || -z "$json" ]]; then
    return 0
  fi

  # sbctl list-files --json returns either an array of objects or a dict keyed by path
  echo "$json" | jq -r '
    if type == "array" then
      .[].file // empty
    elif type == "object" then
      keys[]
    else
      empty
    end
  ' 2>/dev/null
}
