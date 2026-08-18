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
legacy_command="${STAGE_DIR}${PREFIX}/bin/omarchy-secureboot"
canonical_lib="${STAGE_DIR}${PREFIX}/lib/omasecboot"
legacy_lib="${STAGE_DIR}${PREFIX}/lib/omarchy-secureboot"
canonical_state="${STAGE_DIR}/var/lib/omasecboot"
legacy_state="${STAGE_DIR}/var/lib/omarchy-secureboot"
cleanup_hook_name=zz-omasecboot-cleanup.hook
sbctl_hook_name=zz-sbctl.hook
repair_hook_name=zzz-omasecboot.hook
cleanup_hook="${STAGE_DIR}/etc/pacman.d/hooks/${cleanup_hook_name}"
repair_hook="${STAGE_DIR}/etc/pacman.d/hooks/${repair_hook_name}"
limine_hook="${STAGE_DIR}/etc/boot/hooks/post.d/zzz-omasecboot-sign"
legacy_cleanup_hook="${STAGE_DIR}/etc/pacman.d/hooks/zz-omarchy-secureboot-cleanup.hook"
legacy_repair_hook="${STAGE_DIR}/etc/pacman.d/hooks/zzz-omarchy-secureboot.hook"
legacy_limine_hook="${STAGE_DIR}/etc/boot/hooks/post.d/zzz-omarchy-secureboot-sign"

install -Dm755 /dev/null "$legacy_command"
install -Dm644 /dev/null "${legacy_lib}/legacy-file"
install -Dm644 /dev/null "${legacy_state}/windows-enabled"
printf 'legacy\n' > "${legacy_state}/windows-enabled"
install -Dm644 /dev/null "${legacy_state}/repair.lock"
install -Dm644 /dev/null "$legacy_cleanup_hook"
install -Dm644 /dev/null "$legacy_repair_hook"
install -Dm755 /dev/null "$legacy_limine_hook"
make -s -C "$ROOT_DIR" install DESTDIR="$STAGE_DIR" PREFIX="$PREFIX" >/dev/null

[[ -x "$canonical" ]] || fail "canonical command was not installed"
[[ ! -e "$legacy_command" && ! -L "$legacy_command" ]] || fail "legacy command still exists"
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
[[ -f "${canonical_state}/windows-enabled" ]] \
  || fail "Windows opt-in state was not migrated"
grep -Fxq 'legacy' "${canonical_state}/windows-enabled" \
  || fail "Windows opt-in state contents were not preserved"
[[ ! -e "${canonical_state}/repair.lock" ]] \
  || fail "ephemeral repair lock was migrated"
[[ ! -e "$legacy_lib" && ! -e "$legacy_state" ]] \
  || fail "legacy library or state path survived migration"
[[ ! -e "$legacy_cleanup_hook" && ! -e "$legacy_repair_hook" \
   && ! -e "$legacy_limine_hook" ]] \
  || fail "a legacy hook survived migration"
[[ "$cleanup_hook_name" < "$sbctl_hook_name" ]] \
  || fail "cleanup hook no longer sorts before sbctl"
[[ "$sbctl_hook_name" < "$repair_hook_name" ]] \
  || fail "repair hook no longer sorts after sbctl"

printf 'canonical\n' > "${canonical_state}/windows-enabled"
install -Dm644 /dev/null "${legacy_state}/windows-enabled"
printf 'legacy\n' > "${legacy_state}/windows-enabled"
make -s -C "$ROOT_DIR" install DESTDIR="$STAGE_DIR" PREFIX="$PREFIX" >/dev/null
grep -Fxq 'canonical' "${canonical_state}/windows-enabled" \
  || fail "idempotent install replaced canonical Windows opt-in state"

make -s -C "$ROOT_DIR" uninstall DESTDIR="$STAGE_DIR" PREFIX="$PREFIX" >/dev/null

[[ ! -e "$canonical" ]] || fail "canonical command survived uninstall"
[[ ! -e "$legacy_command" ]] || fail "legacy command survived uninstall"
[[ ! -e "$canonical_lib" && ! -e "$legacy_lib" ]] \
  || fail "a library path survived uninstall"
[[ ! -e "$cleanup_hook" && ! -e "$repair_hook" && ! -e "$limine_hook" ]] \
  || fail "a hook survived uninstall"
[[ ! -e "$legacy_cleanup_hook" && ! -e "$legacy_repair_hook" \
   && ! -e "$legacy_limine_hook" ]] \
  || fail "a legacy hook survived uninstall"
[[ ! -e "$canonical_state" && ! -e "$legacy_state" ]] \
  || fail "a state path survived uninstall"

printf 'install tests passed\n'
