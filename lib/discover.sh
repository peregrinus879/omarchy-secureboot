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
list_enrolled_entries() {
  local json
  json=$(sbctl list-files --json 2>/dev/null) || return 0

  if [[ "$json" == "null" || -z "$json" ]]; then
    return 0
  fi

  # sbctl list-files --json has changed shape across releases. Normalize it to
  # tab-separated "file<TAB>output_file" rows for downstream callers.
  echo "$json" | jq -r '
    def rows:
      if type == "array" then .
      elif type == "object" and (has("file") or has("output_file")) then [.] 
      elif type == "object" and has("files") then .files
      elif type == "object" and ([keys[] | startswith("/")] | all) then [.[]]
      else []
      end;

    rows[]
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
