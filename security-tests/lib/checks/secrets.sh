#!/usr/bin/env bash
# Secret leak checks

# Patterns that indicate leaked secrets
SECRET_PATTERNS=(
  "sk-[a-zA-Z0-9]{20,}"
  "sk-proj-[a-zA-Z0-9]{20,}"
  "ghp_[a-zA-Z0-9]{36}"
  "gho_[a-zA-Z0-9]{36}"
  "AKIA[0-9A-Z]{16}"
  "-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----"
  "xox[bpas]-[0-9a-zA-Z-]+"
  "hooks\.slack\.com/services/T"
)

check_no_secrets() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local found_any=false

  for file in "$config_dir"/*.json5 "$config_dir"/*.yaml "$config_dir"/*.yml; do
    [[ -f "$file" ]] || continue
    for pattern in "${SECRET_PATTERNS[@]}"; do
      if grep -qE "$pattern" "$file" 2>/dev/null; then
        local basename
        basename=$(basename "$file")
        record_fail "$desc (найден в ${basename}: pattern '${pattern:0:20}...')" "$sev" "$id"
        found_any=true
        break 2
      fi
    done
  done

  if ! $found_any; then
    record_pass "$desc" "$sev" "$id"
  fi
}

check_no_secrets_env() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/.env"

  if [[ ! -f "$file" ]]; then
    record_skip "$desc (.env не найден)" "$sev" "$id"
    return
  fi

  for pattern in "${SECRET_PATTERNS[@]}"; do
    if grep -qE "$pattern" "$file" 2>/dev/null; then
      record_fail "$desc (хардкоженный секрет в .env!)" "$sev" "$id"
      return
    fi
  done

  record_pass "$desc" "$sev" "$id"
}

check_env_token_set() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local env_file="$config_dir/.env"
  local gw_file="$config_dir/gateway.json5"

  # Check if auth is token-based
  if [[ -f "$gw_file" ]] && grep -q 'mode:.*"token"' "$gw_file" 2>/dev/null; then
    if [[ -f "$env_file" ]]; then
      local token_val
      token_val=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$env_file" 2>/dev/null | cut -d= -f2)
      if [[ -z "$token_val" ]]; then
        record_fail "$desc (OPENCLAW_GATEWAY_TOKEN пустой!)" "$sev" "$id"
      else
        record_pass "$desc" "$sev" "$id"
      fi
    else
      record_warn "$desc (.env не найден, проверьте вручную)" "$sev" "$id"
    fi
  else
    record_skip "$desc (auth ≠ token)" "$sev" "$id"
  fi
}
