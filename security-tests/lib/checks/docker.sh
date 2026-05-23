#!/usr/bin/env bash
# Docker security checks

check_docker_network_internal() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/docker-compose.yml"

  if [[ ! -f "$file" ]]; then
    record_skip "$desc (docker-compose.yml не найден)" "$sev" "$id"
    return
  fi

  if grep -q "internal: true" "$file" 2>/dev/null; then
    record_pass "$desc" "$sev" "$id"
  else
    record_fail "$desc (сеть НЕ internal — возможен выход в интернет!)" "$sev" "$id"
  fi
}

check_docker_no_host_network() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/docker-compose.yml"

  if [[ ! -f "$file" ]]; then
    record_skip "$desc (docker-compose.yml не найден)" "$sev" "$id"
    return
  fi

  if grep -q "network_mode:.*host" "$file" 2>/dev/null; then
    record_fail "$desc (найден network_mode: host!)" "$sev" "$id"
  else
    record_pass "$desc" "$sev" "$id"
  fi
}

check_docker_security_hardened() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/docker-compose.yml"

  if [[ ! -f "$file" ]]; then
    record_skip "$desc (docker-compose.yml не найден)" "$sev" "$id"
    return
  fi

  local score=0
  local total=3

  grep -q "cap_drop:" "$file" 2>/dev/null && ((score++))
  grep -q "no-new-privileges" "$file" 2>/dev/null && ((score++))
  grep -q "read_only: true" "$file" 2>/dev/null && ((score++))

  if [[ "$score" -eq "$total" ]]; then
    record_pass "$desc (${score}/${total})" "$sev" "$id"
  elif [[ "$score" -ge 2 ]]; then
    record_warn "$desc (${score}/${total} — частично)" "$sev" "$id"
  else
    record_warn "$desc (${score}/${total} — минимальный hardening)" "$sev" "$id"
  fi
}
