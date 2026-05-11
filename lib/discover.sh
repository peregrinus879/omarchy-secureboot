#!/bin/bash
# omarchy-secureboot: EFI file discovery and sbctl database queries

# Find all signable EFI files under the ESP.
# Excludes Microsoft files (trusted via -m enrollment), 32-bit bootloader, backups.
discover_efi_files() {
  find "${ESP}" -type f \( \
    -name "*.efi" -o \
    -name "*.EFI" -o \
    -name "*.efi_sha1_*" -o \
    -name "*.efi_sha256_*" -o \
    -name "*.efi_b3_*" -o \
    -name "*.efi_blake3_*" -o \
    -name "*.efi_xxh_*" -o \
    -name "*.efi_xxhash_*" \
  \) \
    ! -path "*/Microsoft/*" \
    ! -name "BOOTIA32.EFI" \
    ! -name "*.bak" \
    2>/dev/null | sort
}

# Resolve the sbctl file database path, honoring local overrides.
resolve_sbctl_files_db_path() {
  local config="/etc/sbctl/sbctl.conf"
  local files_db=""

  if [[ -f "$config" ]]; then
    files_db=$(awk -F': ' '/^[[:space:]]*files_db:[[:space:]]*/ {print $2; exit}' "$config" 2>/dev/null)
  fi

  if [[ -n "$files_db" ]]; then
    printf '%s\n' "$files_db"
    return 0
  fi

  local candidate
  for candidate in \
    /var/lib/sbctl/files.db \
    /var/lib/sbctl/files.json \
    /usr/share/secureboot/files.db \
    /usr/share/secureboot/files.json; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "/var/lib/sbctl/files.db"
  return 0
}

resolve_sbctl_files_db() {
  local files_db
  files_db=$(resolve_sbctl_files_db_path) || return 1
  [[ -f "$files_db" ]] || return 1
  printf '%s\n' "$files_db"
}

# Query tracked files through sbctl's public CLI.
# Returns 0 on success (including empty), 1 on lookup failure.
list_enrolled_entries_from_cli() {
  command -v sbctl >/dev/null 2>&1 || return 1

  local json
  json=$(sbctl list-files --json 2>/dev/null) || return 1
  [[ -n "$json" && "$json" != "null" ]] || return 1

  echo "$json" | jq -r '
    def row($file; $output):
      select(($file // "") != "")
      | [($file), ($output // $file)]
      | @tsv;

    if type == "array" then
      .[]
      | if type == "object" then
          row((.file // .path // .source // ""); (.output_file // .output // .file // .path // .source // ""))
        elif type == "string" then
          row(.; .)
        else
          empty
        end
    elif type == "object" then
      to_entries[]
      | if (.value | type) == "object" then
          row((.value.file // .key); (.value.output_file // .value.output // .value.file // .key))
        elif (.value | type) == "string" then
          row(.key; .value)
        else
          row(.key; .key)
        end
    else
      empty
    end
  ' 2>/dev/null
}

# Query tracked files from sbctl's on-disk database. This is a fallback path
# for stale-entry cleanup and sbctl compatibility logic, not the primary source
# of truth for normal status checks.
list_enrolled_entries_from_db() {
  local files_db db_rc=0 json
  files_db=$(resolve_sbctl_files_db) || db_rc=$?
  if [[ $db_rc -ne 0 ]]; then
    return 1
  fi

  json=$(<"$files_db") || return 1

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

# List file paths currently registered in sbctl's database.
# Returns 0 on success (including empty), 1 on lookup failure.
# CLI success with empty output is authoritative (no DB fallback).
# DB fallback only triggers when CLI fails.
list_enrolled_entries() {
  local cli_entries cli_rc=0
  cli_entries=$(list_enrolled_entries_from_cli) || cli_rc=$?

  if [[ $cli_rc -eq 0 ]]; then
    # CLI succeeded; result is authoritative even if empty
    [[ -n "$cli_entries" ]] && printf '%s\n' "$cli_entries"
    return 0
  fi

  # CLI failed; fall back to on-disk database
  list_enrolled_entries_from_db
}

# Cleanup must catch stale entries even if sbctl's CLI view is incomplete.
# Prefer CLI rows, but merge in database rows when the database is readable.
list_enrolled_entries_for_cleanup() {
  local cli_entries="" db_entries=""
  local cli_rc=0 db_rc=0

  cli_entries=$(list_enrolled_entries_from_cli) || cli_rc=$?
  db_entries=$(list_enrolled_entries_from_db) || db_rc=$?

  if [[ $cli_rc -ne 0 && $db_rc -ne 0 ]]; then
    return 1
  fi

  {
    [[ $cli_rc -ne 0 || -z "$cli_entries" ]] || printf '%s\n' "$cli_entries"
    [[ $db_rc -ne 0 || -z "$db_entries" ]] || printf '%s\n' "$db_entries"
  } | sort -u
}

# Extract output file paths from enrolled entries.
# Returns 0 on success (including empty), 1 on lookup failure.
list_enrolled_paths() {
  local entries rc=0
  entries=$(list_enrolled_entries) || rc=$?
  if [[ $rc -ne 0 ]]; then
    return 1
  fi
  [[ -z "$entries" ]] && return 0

  local file output
  while IFS=$'\t' read -r file output; do
    printf '%s\n' "${output:-$file}"
  done <<< "$entries"
}
