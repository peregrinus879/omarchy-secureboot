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
canonical_lib="${STAGE_DIR}${PREFIX}/lib/omasecboot"
canonical_state="${STAGE_DIR}/var/lib/omasecboot"
cleanup_hook_name=zz-omasecboot-cleanup.hook
sbctl_hook_name=zz-sbctl.hook
repair_hook_name=zzz-omasecboot.hook
cleanup_hook="${STAGE_DIR}/etc/pacman.d/hooks/${cleanup_hook_name}"
repair_hook="${STAGE_DIR}/etc/pacman.d/hooks/${repair_hook_name}"
limine_hook="${STAGE_DIR}/etc/boot/hooks/post.d/zzz-omasecboot-sign"

make -s -C "$ROOT_DIR" install DESTDIR="$STAGE_DIR" PREFIX="$PREFIX" >/dev/null

[[ -x "$canonical" ]] || fail "canonical command was not installed"
for version_arg in version --version -v; do
  if "$canonical" "$version_arg" >/dev/null 2>&1; then
    fail "removed version form succeeded: ${version_arg}"
  fi
done

grep -Fxq "Exec = ${PREFIX}/bin/omasecboot --quiet cleanup" "$cleanup_hook" \
  || fail "cleanup hook does not target the canonical command"
grep -Fxq "Exec = ${PREFIX}/bin/omasecboot --quiet sign" "$repair_hook" \
  || fail "repair hook does not target the canonical command"
grep -Fxq "exec ${PREFIX}/bin/omasecboot --quiet sign" "$limine_hook" \
  || fail "Limine hook does not target the canonical command"
grep -Fxq 'export OMASECBOOT_IN_LIMINE_HOOK=true' "$limine_hook" \
  || fail "Limine hook does not export the canonical sentinel"

[[ -x "${STAGE_DIR}${PREFIX}/bin/omasecboot" ]] \
  || fail "rendered hook target is not executable in the stage"
grep -Fq "$STAGE_DIR" "$cleanup_hook" \
  && fail "DESTDIR leaked into a runtime hook target"

[[ -d "$canonical_lib" ]] || fail "canonical library path is missing"
[[ -d "$canonical_state" ]] || fail "canonical state path is missing"
[[ ! -e "${canonical_state}/repair.lock" ]] \
  || fail "install created an ephemeral repair lock"
[[ "$cleanup_hook_name" < "$sbctl_hook_name" ]] \
  || fail "cleanup hook no longer sorts before sbctl"
[[ "$sbctl_hook_name" < "$repair_hook_name" ]] \
  || fail "repair hook no longer sorts after sbctl"

printf 'canonical\n' > "${canonical_state}/windows-enabled"
make -s -C "$ROOT_DIR" install DESTDIR="$STAGE_DIR" PREFIX="$PREFIX" >/dev/null
grep -Fxq 'canonical' "${canonical_state}/windows-enabled" \
  || fail "idempotent install replaced canonical Windows opt-in state"

make -s -C "$ROOT_DIR" uninstall DESTDIR="$STAGE_DIR" PREFIX="$PREFIX" >/dev/null

[[ ! -e "$canonical" ]] || fail "canonical command survived uninstall"
[[ ! -e "$canonical_lib" ]] || fail "library path survived uninstall"
[[ ! -e "$cleanup_hook" && ! -e "$repair_hook" && ! -e "$limine_hook" ]] \
  || fail "a hook survived uninstall"
[[ ! -e "$canonical_state" ]] || fail "state path survived uninstall"

printf 'install tests passed\n'
