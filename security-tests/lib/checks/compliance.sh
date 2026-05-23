#!/usr/bin/env bash
# Compliance checks

check_compliance() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local env_file="$config_dir/.env"

  if [[ ! -f "$env_file" ]]; then
    record_skip "$desc (.env не найден)" "$sev" "$id"
    return
  fi

  local comp_enabled
  comp_enabled=$(grep "^COMPLIANCE_ENABLED=" "$env_file" 2>/dev/null | cut -d= -f2)

  if [[ "$comp_enabled" == "y" ]]; then
    local comp_url
    comp_url=$(grep "^COMPLIANCE_URL=" "$env_file" 2>/dev/null | cut -d= -f2)

    if [[ -z "$comp_url" ]]; then
      record_warn "$desc (включён, но URL не задан)" "$sev" "$id"
    elif curl -sf -m 3 "$comp_url" &>/dev/null; then
      record_pass "$desc (endpoint доступен: ${comp_url})" "$sev" "$id"
    else
      record_warn "$desc (endpoint недоступен: ${comp_url})" "$sev" "$id"
    fi
  else
    record_warn "$desc (compliance не настроен — необязательно)" "$sev" "$id"
  fi
}
