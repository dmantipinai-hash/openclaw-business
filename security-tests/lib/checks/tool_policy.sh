#!/usr/bin/env bash
# Tool Policy checks

check_file_exists() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  # File param extracted from checks.yaml — we use common names
  local file=""
  case "$id" in
    tool-policy-exists) file="$config_dir/tool-policy.yaml" ;;
    gateway-config-exists) file="$config_dir/gateway.json5" ;;
    *) file="$config_dir/tool-policy.yaml" ;;
  esac

  if [[ -f "$file" ]]; then
    record_pass "$desc" "$sev" "$id"
  else
    record_fail "$desc (${file} не найден)" "$sev" "$id"
  fi
}

check_yaml_contains() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/tool-policy.yaml"

  if [[ ! -f "$file" ]]; then
    record_fail "$desc (файл не найден)" "$sev" "$id"
    return
  fi

  # Simple grep-based YAML check
  if grep -q "profile:.*deny-all" "$file" 2>/dev/null; then
    record_pass "$desc" "$sev" "$id"
  else
    record_fail "$desc (профиль не deny-all)" "$sev" "$id"
  fi
}

check_yaml_in_list() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/tool-policy.yaml"

  if [[ ! -f "$file" ]]; then
    record_fail "$desc (файл не найден)" "$sev" "$id"
    return
  fi

  # Extract the tool name from description (last word before context)
  local tool=""
  case "$id" in
    tool-policy-web-search-blocked) tool="web_search" ;;
    tool-policy-web-fetch-blocked) tool="web_fetch" ;;
    tool-policy-browser-blocked) tool="browser" ;;
    *) tool="unknown" ;;
  esac

  # Check in deny list
  local in_deny=false
  local in_allow=false

  # Simple approach: check if tool appears after "deny:" and before next top-level key
  if awk "/^  deny:/,/^[^ ]/{if(/$tool/) exit 0} END{exit 1}" "$file" 2>/dev/null; then
    in_deny=true
  fi
  if awk "/^  allow:/,/^[^ ]/{if(/$tool/) exit 0} END{exit 1}" "$file" 2>/dev/null; then
    in_allow=true
  fi

  if $in_deny; then
    record_pass "$desc (${tool} в deny-списке)" "$sev" "$id"
  elif $in_allow; then
    record_fail "$desc (${tool} РАЗРЕШЁН!)" "$sev" "$id"
  else
    # Not in either list — depends on profile
    if grep -q "deny-all" "$file"; then
      record_pass "$desc (${tool} не в allow — заблокирован deny-all)" "$sev" "$id"
    else
      record_warn "$desc (${tool} не найден ни в allow, ни в deny)" "$sev" "$id"
    fi
  fi
}

check_tool_blocked_or_restricted() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/tool-policy.yaml"

  if [[ ! -f "$file" ]]; then
    record_fail "$desc (файл не найден)" "$sev" "$id"
    return
  fi

  local tool="web_fetch"

  # In deny list?
  if awk "/^  deny:/,/^[^ ]/{if(/$tool/) exit 0} END{exit 1}" "$file" 2>/dev/null; then
    record_pass "$desc (${tool} заблокирован)" "$sev" "$id"
  elif grep -q "allowedDomains:" "$file" 2>/dev/null; then
    record_pass "$desc (${tool} ограничен allowedDomains)" "$sev" "$id"
  elif grep -q "deny-all" "$file" && ! awk "/^  allow:/,/^[^ ]/{if(/$tool/) exit 0} END{exit 1}" "$file" 2>/dev/null; then
    record_pass "$desc (${tool} заблокирован deny-all)" "$sev" "$id"
  else
    record_warn "$desc (${tool} может быть неограничен)" "$sev" "$id"
  fi
}

check_exec_restricted() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  local file="$config_dir/tool-policy.yaml"

  if [[ ! -f "$file" ]]; then
    record_fail "$desc (файл не найден)" "$sev" "$id"
    return
  fi

  # exec disabled?
  if grep -q "disabled: true" "$file" 2>/dev/null && grep -B5 "disabled: true" "$file" | grep -q "exec"; then
    record_pass "$desc (exec disabled)" "$sev" "$id"
  # exec in deny list?
  elif awk "/^  deny:/,/^[^ ]/{if(/exec/) exit 0} END{exit 1}" "$file" 2>/dev/null; then
    record_pass "$desc (exec в deny-списке)" "$sev" "$id"
  # exec in allow + sandbox?
  elif awk "/^  allow:/,/^[^ ]/{if(/exec/) exit 0} END{exit 1}" "$file" 2>/dev/null; then
    if grep -q "sandbox:" "$file" 2>/dev/null; then
      record_pass "$desc (exec разрешён в sandbox)" "$sev" "$id"
    else
      record_warn "$desc (exec разрешён БЕЗ sandbox!)" "$sev" "$id"
    fi
  else
    # Not mentioned — deny-all blocks it
    if grep -q "deny-all" "$file"; then
      record_pass "$desc (exec заблокирован deny-all)" "$sev" "$id"
    else
      record_warn "$desc (exec статус неясен)" "$sev" "$id"
    fi
  fi
}
