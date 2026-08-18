#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/omasecboot-install.XXXXXX")
PREFIX=/opt/omasecboot-test

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

canonical="${STAGE_DIR}${PREFIX}/bin/omasecboot"
legacy="${STAGE_DIR}${PREFIX}/bin/omarchy-secureboot"
cleanup_hook_name=zz-omarchy-secureboot-cleanup.hook
sbctl_hook_name=zz-sbctl.hook
repair_hook_name=zzz-omarchy-secureboot.hook
cleanup_hook="${STAGE_DIR}/etc/pacman.d/hooks/${cleanup_hook_name}"
repair_hook="${STAGE_DIR}/etc/pacman.d/hooks/${repair_hook_name}"
limine_hook="${STAGE_DIR}/etc/boot/hooks/post.d/zzz-omarchy-secureboot-sign"

install -Dm755 /dev/null "$legacy"
make -s -C "$ROOT_DIR" install DESTDIR="$STAGE_DIR" PREFIX="$PREFIX" >/dev/null

[[ -x "$canonical" ]] || fail "canonical command was not installed"
[[ ! -e "$legacy" && ! -L "$legacy" ]] || fail "legacy command still exists"
[[ $("$canonical" version) == "omasecboot 2.0.0" ]] || fail "unexpected version output"

grep -Fxq "Exec = ${PREFIX}/bin/omasecboot --quiet cleanup" "$cleanup_hook" \
  || fail "cleanup hook does not target the canonical command"
grep -Fxq "Exec = ${PREFIX}/bin/omasecboot --quiet sign" "$repair_hook" \
  || fail "repair hook does not target the canonical command"
grep -Fxq "exec ${PREFIX}/bin/omasecboot --quiet sign" "$limine_hook" \
  || fail "Limine hook does not target the canonical command"

[[ -x "${STAGE_DIR}${PREFIX}/bin/omasecboot" ]] \
  || fail "rendered hook target is not executable in the stage"
grep -Fq "$STAGE_DIR" "$cleanup_hook" \
  && fail "DESTDIR leaked into a runtime hook target"

[[ -d "${STAGE_DIR}${PREFIX}/lib/omarchy-secureboot" ]] \
  || fail "compatibility library path is missing"
[[ -d "${STAGE_DIR}/var/lib/omarchy-secureboot" ]] \
  || fail "compatibility state path is missing"
[[ "$cleanup_hook_name" < "$sbctl_hook_name" ]] \
  || fail "cleanup hook no longer sorts before sbctl"
[[ "$sbctl_hook_name" < "$repair_hook_name" ]] \
  || fail "repair hook no longer sorts after sbctl"

make -s -C "$ROOT_DIR" uninstall DESTDIR="$STAGE_DIR" PREFIX="$PREFIX" >/dev/null

[[ ! -e "$canonical" ]] || fail "canonical command survived uninstall"
[[ ! -e "$legacy" ]] || fail "legacy command survived uninstall"
[[ ! -e "${STAGE_DIR}${PREFIX}/lib/omarchy-secureboot" ]] \
  || fail "library path survived uninstall"
[[ ! -e "$cleanup_hook" && ! -e "$repair_hook" && ! -e "$limine_hook" ]] \
  || fail "a hook survived uninstall"
[[ ! -e "${STAGE_DIR}/var/lib/omarchy-secureboot" ]] \
  || fail "state path survived uninstall"

printf 'install tests passed\n'
