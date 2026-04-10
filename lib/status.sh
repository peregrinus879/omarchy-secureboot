#!/bin/bash
# omarchy-secureboot: status display and file verification

show_status() {
  header "Secure Boot Status"
  local all_ok=true

  # Parse sbctl status
  local json
  json=$(sbctl status --json 2>/dev/null) || true

  if [[ -z "$json" || "$json" == "null" ]]; then
    # Fallback to raw output
    sbctl status
    echo
  else
    local installed setup_mode secure_boot vendors
    read -r installed setup_mode secure_boot < <(
      echo "$json" | jq -r '[.installed, .setup_mode, .secure_boot] | map(. // false) | @tsv'
    )
    vendors=$(echo "$json" | jq -r '
      .vendors // [] | if type == "array" then
        map(tostring) | sort | unique | join(", ")
      else
        tostring
      end
    ')

    if [[ "$installed" == "true" ]]; then
      pass "sbctl keys installed"
    else
      fail "sbctl keys not installed"
      all_ok=false
    fi

    if [[ "$secure_boot" == "true" ]]; then
      pass "Secure Boot enabled"
    else
      fail "Secure Boot disabled"
      all_ok=false
    fi

    if [[ "$setup_mode" == "true" ]]; then
      warn "Setup Mode active"
    else
      pass "Setup Mode disabled"
    fi
    [[ -n "$vendors" && "$vendors" != "null" ]] && echo -e "  ${DIM}Vendor keys: ${vendors}${NC}"
  fi

  # Hook status
  echo
  if [[ -f /usr/share/libalpm/hooks/zz-sbctl.hook ]]; then
    pass "zz-sbctl.hook present (re-signing)"
  else
    warn "zz-sbctl.hook missing. Run: ${BOLD}sudo pacman -S sbctl${NC}"
  fi

  if [[ -f /etc/pacman.d/hooks/zzz-omarchy-secureboot.hook ]]; then
    pass "zzz-omarchy-secureboot.hook present (package repair)"
  else
    warn "zzz-omarchy-secureboot.hook missing. Run: ${BOLD}sudo make install${NC} from repo"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    local watcher_load_state watcher_enabled_state watcher_active_state
    watcher_load_state=$(systemctl show -p LoadState --value omarchy-secureboot-watcher.path 2>/dev/null || true)
    if [[ "$watcher_load_state" == "loaded" ]]; then
      watcher_enabled_state=$(systemctl is-enabled omarchy-secureboot-watcher.path 2>/dev/null || true)
      watcher_active_state=$(systemctl is-active omarchy-secureboot-watcher.path 2>/dev/null || true)

      if [[ "$watcher_enabled_state" == "enabled" ]]; then
        pass "omarchy-secureboot-watcher.path enabled"
      else
        warn "omarchy-secureboot-watcher.path not enabled (${watcher_enabled_state:-unknown})"
      fi

      if [[ "$watcher_active_state" == "active" ]]; then
        pass "omarchy-secureboot-watcher.path active"
      else
        warn "omarchy-secureboot-watcher.path not active (${watcher_active_state:-unknown})"
      fi
    else
      warn "omarchy-secureboot-watcher.path missing. Run: ${BOLD}sudo make install${NC} from repo"
    fi
  fi

  if command -v systemctl >/dev/null 2>&1; then
    local load_state enabled_state active_state
    load_state=$(systemctl show -p LoadState --value limine-snapper-sync.service 2>/dev/null || true)
    if [[ "$load_state" == "loaded" ]]; then
      enabled_state=$(systemctl is-enabled limine-snapper-sync.service 2>/dev/null || true)
      active_state=$(systemctl is-active limine-snapper-sync.service 2>/dev/null || true)

      if [[ "$enabled_state" == "enabled" ]]; then
        pass "limine-snapper-sync.service enabled"
      else
        warn "limine-snapper-sync.service not enabled (${enabled_state:-unknown})"
      fi

      if [[ "$active_state" == "active" ]]; then
        pass "limine-snapper-sync.service active"
      else
        warn "limine-snapper-sync.service not active (${active_state:-unknown})"
        if ! command -v inotifywait >/dev/null 2>&1; then
          echo -e "  ${DIM}Optional upstream watcher helper missing: ${BOLD}inotify-tools${NC}${DIM}. Repo watcher coverage does not depend on it.${NC}"
        fi
      fi
    fi
  fi

  echo
  echo -e "  ${BOLD}Limine Config${NC}"
  if [[ -f /etc/default/limine ]]; then
    if grep -qx 'ENABLE_VERIFICATION=no' /etc/default/limine 2>/dev/null; then
      pass "ENABLE_VERIFICATION=no"
    else
      fail "ENABLE_VERIFICATION is not set to no"
      all_ok=false
    fi

    if grep -qx 'ENABLE_ENROLL_LIMINE_CONFIG=yes' /etc/default/limine 2>/dev/null; then
      pass "ENABLE_ENROLL_LIMINE_CONFIG=yes"
    else
      fail "ENABLE_ENROLL_LIMINE_CONFIG is missing"
      all_ok=false
    fi

    local cmd_before
    cmd_before=$(grep -m1 '^COMMANDS_BEFORE_SAVE=' /etc/default/limine 2>/dev/null | cut -d= -f2-)
    if [[ -n "$cmd_before" ]] && echo "$cmd_before" | tr -d '"' | grep -qw 'limine-reset-enroll'; then
      pass "COMMANDS_BEFORE_SAVE includes limine-reset-enroll"
    else
      fail "COMMANDS_BEFORE_SAVE is missing limine-reset-enroll"
      all_ok=false
    fi

    local cmd_after
    cmd_after=$(grep -m1 '^COMMANDS_AFTER_SAVE=' /etc/default/limine 2>/dev/null | cut -d= -f2-)
    if [[ -n "$cmd_after" ]] && echo "$cmd_after" | tr -d '"' | grep -qw 'limine-enroll-config'; then
      pass "COMMANDS_AFTER_SAVE includes limine-enroll-config"
    else
      fail "COMMANDS_AFTER_SAVE is missing limine-enroll-config"
      all_ok=false
    fi
  else
    fail "/etc/default/limine not found"
    all_ok=false
  fi

  # Windows entry
  if grep -q "# omarchy-secureboot:windows" "$LIMINE_CONF" 2>/dev/null; then
    pass "Windows EFI entry in limine.conf"
  else
    echo -e "  ${DIM}No Windows entry (run ${BOLD}sudo omarchy-secureboot windows${NC}${DIM} to add)${NC}"
  fi

  # Tracked files (root only)
  if [[ $EUID -eq 0 ]]; then
    echo
    echo -e "  ${BOLD}Tracked Files${NC}"
    local -a enrolled
    local -a discovered
    local -a untracked=()
    local file is_signed
    declare -A enrolled_map=()

    mapfile -t enrolled < <(list_enrolled_paths)
    mapfile -t discovered < <(discover_efi_files)

    if [[ ${#enrolled[@]} -eq 0 ]]; then
      warn "No files in sbctl database"
      [[ ${#discovered[@]} -eq 0 ]] || all_ok=false
    else
      for file in "${enrolled[@]}"; do
        enrolled_map["$file"]=1
      done

      for file in "${discovered[@]}"; do
        if [[ -z "${enrolled_map[$file]:-}" ]]; then
          untracked+=("$file")
        fi
      done

      for file in "${enrolled[@]}"; do
        # sbctl verify exits 0 regardless of result; parse JSON for actual status
        is_signed=$(sbctl verify --json "$file" 2>/dev/null \
          | jq -r '.[0].is_signed // empty') || true
        if [[ "$is_signed" == "1" ]]; then
          echo -e "    ${GREEN}✓${NC} $file"
        else
          echo -e "    ${RED}✗${NC} $file"
          all_ok=false
        fi
      done

      if [[ ${#untracked[@]} -gt 0 ]]; then
        echo
        warn "Untracked EFI files found (${#untracked[@]})"
        for file in "${untracked[@]}"; do
          echo -e "    ${YELLOW}!${NC} $file"
        done
        if printf '%s\n' "${untracked[@]}" | grep -q '\.efi_sha256_'; then
          echo -e "  ${DIM}Snapshot UKIs exist outside sbctl's database. The watcher should repair this automatically; run ${BOLD}sudo omarchy-secureboot sign${NC}${DIM} if you need an immediate manual repair.${NC}"
        fi
        all_ok=false
      fi

      echo
      if $all_ok; then
        pass "All tracked files signed and all discovered EFI files enrolled"
      else
        warn "Some files failed. Run: ${BOLD}sudo omarchy-secureboot sign${NC}"
      fi
    fi
  else
    echo
    echo -e "  ${DIM}Run as root for file verification: ${BOLD}sudo omarchy-secureboot status${NC}"
  fi
  echo

  [[ "$all_ok" == true ]]
}
