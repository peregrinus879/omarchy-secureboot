#!/bin/bash
# omarchy-secureboot: status display and file verification

show_status() {
  command -v sbctl >/dev/null 2>&1 || { header "Secure Boot Status"; die "sbctl not installed"; }
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

  # Windows entry
  if grep -q "# omarchy-secureboot:windows" "$LIMINE_CONF" 2>/dev/null; then
    pass "Windows chainload entry in limine.conf"
  else
    echo -e "  ${DIM}No Windows entry (run ${BOLD}sudo omarchy-secureboot windows${NC}${DIM} to add)${NC}"
  fi

  # Enrolled files (root only)
  if [[ $EUID -eq 0 ]]; then
    echo
    echo -e "  ${BOLD}Enrolled Files${NC}"
    local -a enrolled
    mapfile -t enrolled < <(list_enrolled_paths)
    if [[ ${#enrolled[@]} -eq 0 ]]; then
      warn "No files in sbctl database"
    else
      local file all_ok=true
      for file in "${enrolled[@]}"; do
        if sbctl verify "$file" >/dev/null 2>&1; then
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
}
