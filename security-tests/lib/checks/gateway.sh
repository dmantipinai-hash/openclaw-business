#!/usr/bin/env bash
# Gateway config checks

check_gateway_bind() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/gateway.json5"

  if [[ ! -f "$file" ]]; then
    record_fail "$desc" "$sev" "$id"
    return
  fi

  if grep -q 'bind:.*0\.0\.0\.0' "$file" 2>/dev/null; then
    record_fail "$desc (bind=0.0.0.0 — публичный доступ!)" "$sev" "$id"
  else
    record_pass "$desc" "$sev" "$id"
  fi
}

check_gateway_auth() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/gateway.json5"

  if [[ ! -f "$file" ]]; then
    record_fail "$desc (файл не найден)" "$sev" "$id"
    return
  fi

  if grep -q 'mode:.*"none"' "$file" 2>/dev/null; then
    record_fail "$desc (auth=none — без аутентификации!)" "$sev" "$id"
  elif grep -q 'mode:.*"token"' "$file" || grep -q 'mode:.*"trusted-proxy"' "$file"; then
    record_pass "$desc" "$sev" "$id"
  else
    record_warn "$desc (auth mode не определён)" "$sev" "$id"
  fi
}

check_no_external_endpoints() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/gateway.json5"

  if [[ ! -f "$file" ]]; then
    record_skip "$desc" "$sev" "$id"
    return
  fi

  local external_patterns="api\.openai\.com|api\.anthropic\.com|generativelanguage\.googleapis\.com|api\.mistral\.ai"
  if grep -qE "$external_patterns" "$file" 2>/dev/null; then
    local found
    found=$(grep -oE "$external_patterns" "$file" | sort -u | tr '\n' ' ')
    record_fail "$desc (найдены: ${found})" "$sev" "$id"
  else
    record_pass "$desc" "$sev" "$id"
  fi
}

check_no_placeholders() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/${5:-gateway.json5}"

  if [[ ! -f "$file" ]]; then
    record_skip "$desc" "$sev" "$id"
    return
  fi

  if grep -qE '\{\{[A-Z_]+\}\}' "$file" 2>/dev/null; then
    local leftovers
    leftovers=$(grep -oE '\{\{[A-Z_]+\}\}' "$file" | sort -u | tr '\n' ' ')
    record_fail "$desc (незаменённые: ${leftovers})" "$sev" "$id"
  else
    record_pass "$desc" "$sev" "$id"
  fi
}
