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

# Resolve the sbctl file database path, honoring local overrides.
resolve_sbctl_files_db() {
  local config="/etc/sbctl/sbctl.conf"
  local files_db=""

  if [[ -f "$config" ]]; then
    files_db=$(awk -F': ' '/^[[:space:]]*files_db:[[:space:]]*/ {print $2; exit}' "$config" 2>/dev/null)
  fi

  if [[ -n "$files_db" && -f "$files_db" ]]; then
    printf '%s\n' "$files_db"
    return 0
  fi

  if [[ -f /var/lib/sbctl/files.json ]]; then
    printf '%s\n' "/var/lib/sbctl/files.json"
    return 0
  fi

  if [[ -f /var/lib/sbctl/files.db ]]; then
    printf '%s\n' "/var/lib/sbctl/files.db"
    return 0
  fi

  return 1
}

# List file paths currently registered in sbctl's database.
list_enrolled_entries() {
  local files_db json
  files_db=$(resolve_sbctl_files_db) || return 0
  json=$(<"$files_db") || return 0

  if [[ "$json" == "null" || -z "$json" ]]; then
    return 0
  fi

  # sbctl stores signing entries as a JSON object keyed by source file path.
  # Normalize it to tab-separated "file<TAB>output_file" rows.
  echo "$json" | jq -r '
    if type == "object" then .[] else [] end
    | select((.file // .output_file // "") != "")
    | [(.file // .output_file), (.output_file // .file)]
    | @tsv
  ' 2>/dev/null
}

list_enrolled_paths() {
  local file output
  while IFS=$'\t' read -r file output; do
    printf '%s\n' "${output:-$file}"
  done < <(list_enrolled_entries)
}
