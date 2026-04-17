#!/bin/bash
# omarchy-secureboot: shared constants and output helpers

# shellcheck disable=SC2034 # Constants are consumed by sourced lib files.
readonly VERSION="1.0.0"
readonly ESP="/boot"
# shellcheck disable=SC2034 # Used by sourced lib files.
readonly LIMINE_CONF="${ESP}/limine.conf"
# shellcheck disable=SC2034 # Used by sourced lib files.
readonly STATE_DIR="/var/lib/omarchy-secureboot"

# --- Colors ------------------------------------------------------------------

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly DIM='\033[2m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# --- Output helpers ----------------------------------------------------------

header() { echo -e "\n${BOLD}omarchy-secureboot${NC} ${DIM}-${NC} ${BOLD}$*${NC}\n"; }
pass()   { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗${NC} $*"; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
act()    { echo -e "  ${BLUE}→${NC} $*"; }
die()    { fail "$*"; exit 1; }

# Quiet mode: only show errors
QUIET=false
qpass() { [[ "$QUIET" == true ]] || pass "$@"; }
qact()  { [[ "$QUIET" == true ]] || act "$@"; }
qheader() { [[ "$QUIET" == true ]] || header "$@"; }

# --- Locking ----------------------------------------------------------------

with_repair_lock() {
  command -v flock >/dev/null 2>&1 \
    || die "flock not installed. Run: ${BOLD}sudo pacman -S util-linux${NC}"
  mkdir -p "$STATE_DIR"
  exec 9>"${STATE_DIR}/repair.lock"
  flock -w 30 9 || die "Could not acquire repair lock"
}

# --- File helpers -----------------------------------------------------------

backup_file() {
  local file="$1" backup
  [[ -f "$file" ]] || return 1
  backup=$(mktemp "/tmp/omarchy-secureboot.$(basename "$file").XXXXXX") || return 1
  cp -p "$file" "$backup" || {
    rm -f "$backup"
    return 1
  }
  printf '%s\n' "$backup"
}

restore_file_backup() {
  local backup="$1" file="$2"
  cp -p "$backup" "$file"
}

discard_file_backup() {
  rm -f "$1"
}
