#!/bin/bash
# omarchy-secureboot: shared constants and output helpers

readonly VERSION="1.0.0"
readonly ESP="/boot"
readonly LIMINE_CONF="${ESP}/limine.conf"

# --- Colors ------------------------------------------------------------------

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly DIM='\033[2m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# --- Output helpers ----------------------------------------------------------

header() { echo -e "\n${BOLD}omarchy-secureboot${NC} ${DIM}—${NC} ${BOLD}$*${NC}\n"; }
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
