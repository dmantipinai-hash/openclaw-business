#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  OpenClaw Enterprise — Config Validator                      ║
# ║  Проверяет что сгенерированные конфиги корректны            ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

# ─── Colors ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0
CHECKS=0

check_pass() { ((PASS++)); ((CHECKS++)); echo -e "  ${GREEN}✅${NC} $*"; }
check_fail() { ((FAIL++)); ((CHECKS++)); echo -e "  ${RED}❌${NC} $*"; }
check_warn() { ((WARN++)); ((CHECKS++)); echo -e "  ${YELLOW}⚠️${NC} $*"; }

# ─── Args ───────────────────────────────────────────────────────────
CONFIG_DIR="${1:-./output}"

if [[ ! -d "$CONFIG_DIR" ]]; then
  echo -e "${RED}❌ Папка не найдена: $CONFIG_DIR${NC}"
  echo "Использование: ./validate.sh <путь-к-output/>"
  exit 1
fi

echo -e "\n${BOLD}${CYAN}🔍 Validating: ${CONFIG_DIR}/${NC}\n"

# ─── 1. File existence ─────────────────────────────────────────────
echo -e "${BOLD}📁 Файлы${NC}"

if [[ -f "$CONFIG_DIR/gateway.json5" ]]; then
  check_pass "gateway.json5 — найден"
else
  check_fail "gateway.json5 — НЕ НАЙДЕН"
fi

if [[ -f "$CONFIG_DIR/tool-policy.yaml" ]]; then
  check_pass "tool-policy.yaml — найден"
else
  check_fail "tool-policy.yaml — НЕ НАЙДЕН"
fi

if [[ -f "$CONFIG_DIR/docker-compose.yml" ]]; then
  check_pass "docker-compose.yml — найден"
elif [[ -f "$CONFIG_DIR/.env" ]]; then
  check_pass ".env — найден (docker-compose может не быть)"
else
  check_warn "docker-compose.yml — не найден (необязательно)"
fi

# ─── 2. gateway.json5 basic checks ────────────────────────────────
echo -e "\n${BOLD}⚙️ Gateway Config${NC}"

if [[ -f "$CONFIG_DIR/gateway.json5" ]]; then
  # Check it has model config
  if grep -q "models:" "$CONFIG_DIR/gateway.json5"; then
    check_pass "gateway.json5 — содержит секцию models"
  else
    check_fail "gateway.json5 — НЕТ секции models"
  fi

  # Check port is set
  if grep -qE "port: [0-9]+" "$CONFIG_DIR/gateway.json5"; then
    local_port=$(grep -oE "port: [0-9]+" "$CONFIG_DIR/gateway.json5" | head -1 | awk '{print $2}')
    check_pass "gateway.json5 — порт: ${local_port}"
  else
    check_fail "gateway.json5 — порт не задан"
  fi

  # Check no template placeholders left
  if grep -qE '\{\{[A-Z_]+\}\}' "$CONFIG_DIR/gateway.json5"; then
    leftovers=$(grep -oE '\{\{[A-Z_]+\}\}' "$CONFIG_DIR/gateway.json5" | sort -u | tr '\n' ' ')
    check_fail "gateway.json5 — незаменённые плейсхолдеры: ${leftovers}"
  else
    check_pass "gateway.json5 — все плейсхолдеры заменены"
  fi

  # Check auth mode
  if grep -q "mode:" "$CONFIG_DIR/gateway.json5"; then
    check_pass "gateway.json5 — auth mode задан"
  else
    check_warn "gateway.json5 — auth mode не найден"
  fi
fi

# ─── 3. Tool Policy checks ────────────────────────────────────────
echo -e "\n${BOLD}🔒 Tool Policy${NC}"

if [[ -f "$CONFIG_DIR/tool-policy.yaml" ]]; then
  # Check deny-all
  if grep -q "deny-all" "$CONFIG_DIR/tool-policy.yaml"; then
    check_pass "tool-policy — профиль deny-all"
  else
    check_warn "tool-policy — НЕ deny-all (проверьте вручную)"
  fi

  # Check dangerous tools are denied
  for tool in web_search browser; do
    if grep -q "$tool" "$CONFIG_DIR/tool-policy.yaml"; then
      # Check it's in deny section
      if grep -A 20 "^  deny:" "$CONFIG_DIR/tool-policy.yaml" | grep -q "$tool"; then
        check_pass "${tool} — заблокирован"
      elif grep -A 20 "^  allow:" "$CONFIG_DIR/tool-policy.yaml" | grep -q "$tool"; then
        check_fail "${tool} — РАЗРЕШЁН (опасно для enterprise!)"
      fi
    else
      check_pass "${tool} — отсутствует в явном виде"
    fi
  done

  # Check no placeholders
  if grep -qE '\{\{[A-Z_]+\}\}' "$CONFIG_DIR/tool-policy.yaml"; then
    check_fail "tool-policy — содержит незаменённые плейсхолдеры"
  else
    check_pass "tool-policy — все плейсхолдеры заменены"
  fi
fi

# ─── 4. Secret leak check ─────────────────────────────────────────
echo -e "\n${BOLD}🔐 Секреты${NC}"

SECRET_PATTERN="(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC )?PRIVATE KEY-----)"

if [[ -f "$CONFIG_DIR/gateway.json5" ]]; then
  if grep -qE "$SECRET_PATTERN" "$CONFIG_DIR/gateway.json5" 2>/dev/null; then
    check_fail "gateway.json5 — ОБНАРУЖЕН СЕКРЕТ!"
  else
    check_pass "gateway.json5 — секретов не найдено"
  fi
fi

if [[ -f "$CONFIG_DIR/.env" ]]; then
  if grep -qE "$SECRET_PATTERN" "$CONFIG_DIR/.env" 2>/dev/null; then
    check_fail ".env — ОБНАРУЖЕН СЕКРЕТ! (используйте переменные окружения)"
  else
    check_pass ".env — секретов не найдено"
  fi
fi

# ─── 5. Network checks (if endpoints configured) ──────────────────
echo -e "\n${BOLD}🌐 Сеть${NC}"

if [[ -f "$CONFIG_DIR/.env" ]]; then
  LLM_URL=$(grep "^LLM_BASE_URL=" "$CONFIG_DIR/.env" | cut -d= -f2)
  if [[ -n "$LLM_URL" ]]; then
    if curl -sf -m 3 "${LLM_URL%%/v1*}/api/tags" &>/dev/null || \
       curl -sf -m 3 "$LLM_URL" &>/dev/null; then
      check_pass "LLM endpoint (${LLM_URL}) — доступен"
    else
      check_warn "LLM endpoint (${LLM_URL}) — НЕ ДОСТУПЕН (может быть ещё не запущен)"
    fi
  fi

  # Check gateway port not in use
  GW_PORT=$(grep "^GATEWAY_PORT=" "$CONFIG_DIR/.env" | cut -d= -f2)
  if [[ -n "$GW_PORT" ]]; then
    if lsof -i ":${GW_PORT}" &>/dev/null 2>&1; then
      check_warn "Порт ${GW_PORT} занят (запущен другой процесс)"
    else
      check_pass "Порт ${GW_PORT} — свободен"
    fi
  fi
fi

# ─── 6. Kill Switch check ─────────────────────────────────────────
echo -e "\n${BOLD}🔴 Kill Switch${NC}"

if [[ -f "$CONFIG_DIR/.env" ]]; then
  KS_ENABLED=$(grep "^KILLSWITCH_ENABLED=" "$CONFIG_DIR/.env" | cut -d= -f2)
  if [[ "$KS_ENABLED" == "y" ]]; then
    DASH_PORT=$(grep "^DASHBOARD_PORT=" "$CONFIG_DIR/.env" | cut -d= -f2)
    check_pass "Kill Switch — включён (dashboard :${DASH_PORT:-8081})"

    # Try to reach watchdog if it's running
    if curl -sf -m 2 "http://localhost:${DASH_PORT:-8081}" &>/dev/null; then
      check_pass "Kill Switch dashboard — отвечает"
    else
      check_warn "Kill Switch dashboard — не отвечает (ещё не запущен?)"
    fi
  else
    check_warn "Kill Switch — отключён"
  fi
fi

# ─── 7. Compliance check ──────────────────────────────────────────
echo -e "\n${BOLD}📋 Compliance${NC}"

if [[ -f "$CONFIG_DIR/.env" ]]; then
  COMP_ENABLED=$(grep "^COMPLIANCE_ENABLED=" "$CONFIG_DIR/.env" | cut -d= -f2)
  if [[ "$COMP_ENABLED" == "y" ]]; then
    COMP_URL=$(grep "^COMPLIANCE_URL=" "$CONFIG_DIR/.env" | cut -d= -f2)
    if curl -sf -m 3 "$COMP_URL" &>/dev/null; then
      check_pass "Compliance endpoint (${COMP_URL}) — доступен"
    else
      check_warn "Compliance endpoint (${COMP_URL}) — НЕ ДОСТУПЕН"
    fi
  else
    check_warn "Compliance — не настроен (необязательно)"
  fi
fi

# ─── Summary ───────────────────────────────────────────────────────
echo -e "\n${BOLD}═══════════════════════════════════════${NC}"
echo -e "${BOLD} Итого: ${CHECKS} проверок${NC}"
echo -e " ${GREEN}✅ Pass: ${PASS}${NC}"
echo -e " ${YELLOW}⚠️  Warn: ${WARN}${NC}"
echo -e " ${RED}❌ Fail: ${FAIL}${NC}"
echo -e "${BOLD}═══════════════════════════════════════${NC}"

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "\n${RED}${BOLD}⛔ Есть критические проблемы. Исправьте перед запуском.${NC}\n"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  echo -e "\n${YELLOW}${BOLD}⚠️  Есть предупреждения. Можно запускать, но проверьте.${NC}\n"
  exit 0
else
  echo -e "\n${GREEN}${BOLD}🎉 Всё чисто! Можно запускать.${NC}\n"
  exit 0
fi
