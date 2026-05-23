#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  OpenClaw Enterprise — Security Test Suite                    ║
# ║  Проверяет конфигурацию на безопасность                      ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# ─── Colors ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Counters ───────────────────────────────────────────────────────
TOTAL=0
PASS=0
FAIL=0
WARN=0
SKIP=0
RESULTS=()

# ─── Result recorder ───────────────────────────────────────────────
record_pass() {
  ((TOTAL++)); ((PASS++))
  RESULTS+=("pass|$1|$2|$3")
  echo -e "  ${GREEN}✅${NC} ${DIM}[$2]${NC} $1"
}

record_fail() {
  ((TOTAL++)); ((FAIL++))
  RESULTS+=("fail|$1|$2|$3")
  echo -e "  ${RED}❌${NC} ${DIM}[$2]${NC} $1"
}

record_warn() {
  ((TOTAL++)); ((WARN++))
  RESULTS+=("warn|$1|$2|$3")
  echo -e "  ${YELLOW}⚠️${NC} ${DIM}[$2]${NC} $1"
}

record_skip() {
  ((TOTAL++)); ((SKIP++))
  RESULTS+=("skip|$1|$2|$3")
  echo -e "  ${DIM}⏭️  [$2]${NC} ${DIM}$1${NC}"
}

# ─── Args ───────────────────────────────────────────────────────────
CONFIG_DIR="${1:-./output}"
REPORT_FORMAT="${2:-markdown}"  # markdown | json
REPORT_FILE="$CONFIG_DIR/security-report.md"

if [[ ! -d "$CONFIG_DIR" ]]; then
  echo -e "${RED}❌ Папка не найдена: $CONFIG_DIR${NC}"
  echo "Использование: ./run-tests.sh <config-dir> [markdown|json]"
  exit 1
fi

echo -e "\n${BOLD}${CYAN}🔐 OpenClaw Enterprise — Security Test Suite${NC}"
echo -e "${DIM}   Config: ${CONFIG_DIR}${NC}\n"

# ─── Source check libraries ────────────────────────────────────────
source "$LIB_DIR/checks/gateway.sh"
source "$LIB_DIR/checks/tool_policy.sh"
source "$LIB_DIR/checks/secrets.sh"
source "$LIB_DIR/checks/kill_switch.sh"
source "$LIB_DIR/checks/docker.sh"
source "$LIB_DIR/checks/compliance.sh"

# ─── Run checks from YAML (parsed inline) ─────────────────────────
# Simple YAML parser — reads checks.yaml and runs functions
run_checks() {
  local current_id="" current_cat="" current_sev="" current_desc="" current_test=""

  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    # Parse id
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]id:[[:space:]]*(.+)$ ]]; then
      current_id="${BASH_REMATCH[1]//\"/}"
    elif [[ "$line" =~ ^[[:space:]]*category:[[:space:]]*(.+)$ ]]; then
      current_cat="${BASH_REMATCH[1]//\"/}"
    elif [[ "$line" =~ ^[[:space:]]*severity:[[:space:]]*(.+)$ ]]; then
      current_sev="${BASH_REMATCH[1]//\"/}"
    elif [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*\"(.+)\"$ ]]; then
      current_desc="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*test:[[:space:]]*\"(.+)\"$ ]]; then
      current_test="${BASH_REMATCH[1]}"

      # We have a complete check — run it
      echo -e "${BOLD}Testing: ${current_id}${NC}"

      case "$current_test" in
        file_exists)
          check_file_exists "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        yaml_contains)
          check_yaml_contains "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        yaml_in_list)
          check_yaml_in_list "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        tool_blocked_or_restricted)
          check_tool_blocked_or_restricted "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        exec_restricted)
          check_exec_restricted "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        gateway_bind_check)
          check_gateway_bind "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        gateway_auth_check)
          check_gateway_auth "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        no_external_endpoints)
          check_no_external_endpoints "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        no_placeholders)
          check_no_placeholders "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        no_secrets)
          check_no_secrets "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        no_secrets_env)
          check_no_secrets_env "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        killswitch_configured)
          check_killswitch_configured "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        killswitch_healthcheck)
          check_killswitch_healthcheck "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        docker_network_internal)
          check_docker_network_internal "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        docker_no_host_network)
          check_docker_no_host_network "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        docker_security_hardened)
          check_docker_security_hardened "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        compliance_check)
          check_compliance "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        env_token_set)
          check_env_token_set "$CONFIG_DIR" "$current_id" "$current_sev" "$current_desc"
          ;;
        *)
          record_skip "$current_desc" "$current_sev" "test '${current_test}' not implemented"
          ;;
      esac
      echo ""
    fi
  done < "$SCRIPT_DIR/checks.yaml"
}

# ─── Generate report ───────────────────────────────────────────────
generate_report() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')

  cat > "$REPORT_FILE" <<HDR
# 🔐 Security Test Report

**Дата:** ${timestamp}
**Конфигурация:** ${CONFIG_DIR}

---

## Результаты

| Статус | Проверка | Категория | Важность |
|--------|----------|-----------|----------|
HDR

  for result in "${RESULTS[@]}"; do
    IFS='|' read -r status desc sev cat <<< "$result"
    local icon=""
    case "$status" in
      pass) icon="✅" ;;
      fail) icon="❌" ;;
      warn) icon="⚠️" ;;
      skip) icon="⏭️" ;;
    esac
    echo "| ${icon} | ${desc} | ${sev} | ${cat} |" >> "$REPORT_FILE"
  done

  # Summary
  local score=$(( TOTAL > 0 ? (PASS * 100) / TOTAL : 0 ))
  cat >> "$REPORT_FILE" <<SUM

---

## Итого: ${PASS}/${TOTAL} (${score}%)

**Критические:** $(grep -c "^fail|" <<< "$(printf '%s\n' "${RESULTS[@]}" | grep "critical")" || echo 0) проблем
**Высокие:** $(grep -c "^fail|" <<< "$(printf '%s\n' "${RESULTS[@]}" | grep "high")" || echo 0) проблем
**Средние:** $(grep -c "^(warn\|fail)|" <<< "$(printf '%s\n' "${RESULTS[@]}" | grep "medium")" || echo 0) замечаний
SUM

  # Recommendations for failures
  local has_fails=false
  for result in "${RESULTS[@]}"; do
    IFS='|' read -r status desc sev cat <<< "$result"
    if [[ "$status" == "fail" ]]; then
      if [[ "$has_fails" == false ]]; then
        echo -e "\n### Рекомендации\n" >> "$REPORT_FILE"
        has_fails=true
      fi
      echo -e "❌ **${desc}:** Требуется исправление перед production." >> "$REPORT_FILE"
    fi
  done

  echo -e "\n---\n_Отчёт создан security-tests/run-tests.sh_" >> "$REPORT_FILE"
}

# ─── Main ───────────────────────────────────────────────────────────
run_checks
generate_report

# ─── Console summary ───────────────────────────────────────────────
echo -e "\n${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD} 🔐 Security Test Results${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e " ${GREEN}✅ Pass:${NC} ${PASS}/${TOTAL}"
echo -e " ${RED}❌ Fail:${NC} ${FAIL}/${TOTAL}"
echo -e " ${YELLOW}⚠️  Warn:${NC} ${WARN}/${TOTAL}"
echo -e " ${DIM}⏭️  Skip:${NC} ${SKIP}/${TOTAL}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "\n${RED}${BOLD}⛔ ${FAIL} критических проблем. Исправьте перед запуском.${NC}"
  echo -e "${DIM}   Отчёт: ${REPORT_FILE}${NC}\n"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  echo -e "\n${YELLOW}${BOLD}⚠️  ${WARN} предупреждений. Можно запускать, но проверьте.${NC}"
  echo -e "${DIM}   Отчёт: ${REPORT_FILE}${NC}\n"
  exit 0
else
  echo -e "\n${GREEN}${BOLD}🎉 Все проверки пройдены! Конфигурация безопасна.${NC}"
  echo -e "${DIM}   Отчёт: ${REPORT_FILE}${NC}\n"
  exit 0
fi
