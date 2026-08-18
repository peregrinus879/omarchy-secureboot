#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/omasecboot-windows-migration.XXXXXX")
LIMINE_CONF="${TEST_DIR}/limine.conf"
STATE_DIR="${TEST_DIR}/state"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

backup_file() {
  local backup="${TEST_DIR}/limine.conf.backup"
  cp -p "$1" "$backup" || return 1
  printf '%s\n' "$backup"
}

restore_file_backup() {
  cp -p "$1" "$2"
}

discard_file_backup() {
  rm -f "$1"
}

fail() {
  fail_test "$*"
}

qact() {
  :
}

# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/windows.sh"

find_windows_boot_entry() {
  printf '0007\tWindows Boot Manager\n'
}

mkdir -p "$STATE_DIR"
cat > "$LIMINE_CONF" <<'EOF'
timeout: 5

# omarchy-secureboot:windows
/Windows
    comment: Windows Boot Manager
    protocol: efi_boot_entry
    entry: Windows Boot Manager

/Linux
    protocol: efi
    path: boot():/EFI/Linux/omarchy_linux.efi
EOF

windows_entry_is_configured || fail_test "old marker was not recognized"
ensure_windows_boot_entry || fail_test "old marker migration failed"

[[ $(grep -Fc "$WINDOWS_ENTRY_MARKER" "$LIMINE_CONF") -eq 1 ]] \
  || fail_test "canonical marker was not written exactly once"
if grep -Fq "$LEGACY_WINDOWS_ENTRY_MARKER" "$LIMINE_CONF"; then
  fail_test "old marker survived migration"
fi
[[ $(grep -Fc '/Windows' "$LIMINE_CONF") -eq 1 ]] \
  || fail_test "migration duplicated the Windows entry"
grep -Fq 'timeout: 5' "$LIMINE_CONF" \
  || fail_test "migration dropped unrelated global config"
grep -Fq '/Linux' "$LIMINE_CONF" \
  || fail_test "migration dropped an unrelated entry"

cp -p "$LIMINE_CONF" "${TEST_DIR}/limine.conf.once"
ensure_windows_boot_entry || fail_test "canonical marker recheck failed"
cmp "${TEST_DIR}/limine.conf.once" "$LIMINE_CONF" \
  || fail_test "canonical marker migration was not idempotent"

cat >> "$LIMINE_CONF" <<'EOF'

# omarchy-secureboot:windows
/Windows
    protocol: efi_boot_entry
    entry: Windows Boot Manager
EOF

update_windows_boot_entry "Windows Boot Manager" \
  || fail_test "duplicate marker repair failed"
[[ $(grep -Fc "$WINDOWS_ENTRY_MARKER" "$LIMINE_CONF") -eq 1 ]] \
  || fail_test "duplicate repair did not leave one canonical marker"
[[ $(grep -Fc '/Windows' "$LIMINE_CONF") -eq 1 ]] \
  || fail_test "duplicate repair did not leave one Windows entry"
if grep -Fq "$LEGACY_WINDOWS_ENTRY_MARKER" "$LIMINE_CONF"; then
  fail_test "duplicate repair retained the old marker"
fi

printf 'windows migration tests passed\n'
