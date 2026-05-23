#!/usr/bin/env bash
# Kill Switch checks

check_killswitch_configured() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local env_file="$config_dir/.env"
  local compose_file="$config_dir/docker-compose.yml"

  local found=false

  # Check in .env
  if [[ -f "$env_file" ]] && grep -q "KILLSWITCH_ENABLED=y" "$env_file" 2>/dev/null; then
    found=true
  fi

  # Check in docker-compose
  if [[ -f "$compose_file" ]] && grep -q "watchdog" "$compose_file" 2>/dev/null; then
    found=true
  fi

  if $found; then
    record_pass "$desc" "$sev" "$id"
  else
    record_warn "$desc (Kill Switch не обнаружен)" "$sev" "$id"
  fi
}

check_killswitch_healthcheck() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local env_file="$config_dir/.env"

  local dash_port=8081
  if [[ -f "$env_file" ]]; then
    local port_val
    port_val=$(grep "^DASHBOARD_PORT=" "$env_file" 2>/dev/null | cut -d= -f2)
    [[ -n "$port_val" ]] && dash_port="$port_val"
  fi

  # Try watchdog API directly
  if curl -sf -m 2 "http://localhost:5000/api/status" &>/dev/null; then
    record_pass "$desc (watchdog отвечает на :5000)" "$sev" "$id"
  elif curl -sf -m 2 "http://localhost:${dash_port}" &>/dev/null; then
    record_pass "$desc (dashboard отвечает на :${dash_port})" "$sev" "$id"
  else
    record_warn "$desc (не запущен или недоступен)" "$sev" "$id"
  fi
}
