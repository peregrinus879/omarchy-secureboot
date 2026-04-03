#!/bin/bash
# omarchy-secureboot: status display and file verification

show_status() {
  header "Secure Boot Status"

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

    [[ "$installed" == "true" ]]   && pass "sbctl keys installed"     || fail "sbctl keys not installed"
    [[ "$secure_boot" == "true" ]] && pass "Secure Boot enabled"      || fail "Secure Boot disabled"
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
    pass "zzz-omarchy-secureboot.hook present (snapshot discovery)"
  else
    warn "zzz-omarchy-secureboot.hook missing. Run: ${BOLD}sudo make install${NC} from repo"
  fi

  echo
  echo -e "  ${BOLD}Limine Config${NC}"
  if [[ -f /etc/default/limine ]]; then
    grep -qx 'ENABLE_ENROLL_LIMINE_CONFIG=yes' /etc/default/limine 2>/dev/null \
      && pass "ENABLE_ENROLL_LIMINE_CONFIG=yes" \
      || fail "ENABLE_ENROLL_LIMINE_CONFIG is missing"
    grep -qx 'COMMANDS_BEFORE_SAVE="limine-reset-enroll"' /etc/default/limine 2>/dev/null \
      && pass "COMMANDS_BEFORE_SAVE resets enrollment" \
      || fail "COMMANDS_BEFORE_SAVE is missing limine-reset-enroll"
    grep -qx 'COMMANDS_AFTER_SAVE="limine-enroll-config"' /etc/default/limine 2>/dev/null \
      && pass "COMMANDS_AFTER_SAVE re-enrolls config" \
      || fail "COMMANDS_AFTER_SAVE is missing limine-enroll-config"
  else
    fail "/etc/default/limine not found"
  fi

  # Windows entry
  if grep -q "# omarchy-secureboot:windows" "$LIMINE_CONF" 2>/dev/null; then
    pass "Windows EFI entry in limine.conf"
  else
    echo -e "  ${DIM}No Windows entry (run ${BOLD}sudo omarchy-secureboot windows${NC}${DIM} to add)${NC}"
  fi

  # Tracked files (root only)
  local all_ok=true
  if [[ $EUID -eq 0 ]]; then
    echo
    echo -e "  ${BOLD}Tracked Files${NC}"
    local -a enrolled
    mapfile -t enrolled < <(list_enrolled_paths)
    if [[ ${#enrolled[@]} -eq 0 ]]; then
      warn "No files in sbctl database"
    else
      local file is_signed
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
      echo
      if $all_ok; then
        pass "All files signed and verified"
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
