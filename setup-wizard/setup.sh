#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  OpenClaw Enterprise — Setup Wizard                         ║
# ║  Интерактивная настройка за 5 минут                         ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
OUTPUT_DIR="$REPO_ROOT/output"

# ─── Colors ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ${NC} $*"; }
ok()    { echo -e "${GREEN}✅${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠️${NC} $*"; }
fail()  { echo -e "${RED}❌${NC} $*"; }
header(){ echo -e "\n${BOLD}${BLUE}$*${NC}\n"; }

# ─── Defaults ───────────────────────────────────────────────────────
LLM_PROVIDER=""
LLM_BASE_URL=""
LLM_API_KEY="ollama"
LLM_API_FORMAT="openai-completions"
LLM_MODEL_ID=""
LLM_MODEL_NAME=""
LLM_REASONING="false"
LLM_CONTEXT_WINDOW=131072
LLM_MAX_TOKENS=4096
TOOL_POLICY="strict"
COMPLIANCE_ENABLED="n"
COMPLIANCE_URL=""
KILLSWITCH_ENABLED="y"
DASHBOARD_PORT=8081
AUTH_METHOD="token"
GATEWAY_PORT=18789
GATEWAY_BIND="loopback"
TIMEZONE="Europe/Moscow"
USE_DOCKER="y"

# ─── Non-interactive mode ──────────────────────────────────────────
NON_INTERACTIVE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --llm) LLM_PROVIDER="$2"; shift 2 ;;
    --llm-url) LLM_BASE_URL="$2"; shift 2 ;;
    --llm-model) LLM_MODEL_ID="$2"; shift 2 ;;
    --policy) TOOL_POLICY="$2"; shift 2 ;;
    --compliance) COMPLIANCE_ENABLED="y"; COMPLIANCE_URL="$2"; shift 2 ;;
    --killswitch) KILLSWITCH_ENABLED="y"; shift ;;
    --no-killswitch) KILLSWITCH_ENABLED="n"; shift ;;
    --auth) AUTH_METHOD="$2"; shift 2 ;;
    --port) GATEWAY_PORT="$2"; shift 2 ;;
    --tz) TIMEZONE="$2"; shift 2 ;;
    --no-docker) USE_DOCKER="n"; shift ;;
    --help|-h)
      echo "Usage: ./setup.sh [options]"
      echo ""
      echo "Options:"
      echo "  --non-interactive    Run without prompts (CI mode)"
      echo "  --llm PROVIDER       LLM: ollama | vllm | openai-compatible"
      echo "  --llm-url URL        LLM endpoint URL"
      echo "  --llm-model MODEL    Model ID (e.g. llama3.1:8b)"
      echo "  --policy PROFILE     Tool policy: strict | standard | sandboxed"
      echo "  --compliance URL     Enable compliance logging to URL"
      echo "  --killswitch         Enable Kill Switch (default)"
      echo "  --no-killswitch      Disable Kill Switch"
      echo "  --auth METHOD        Auth: token | none"
      echo "  --port PORT          Gateway port (default: 18789)"
      echo "  --tz TIMEZONE        Timezone (default: Europe/Moscow)"
      echo "  --no-docker          Generate configs without Docker"
      exit 0 ;;
    *) fail "Unknown option: $1"; exit 1 ;;
  esac
done

# ─── Dependency check ───────────────────────────────────────────────
check_deps() {
  header "🔍 Проверка зависимостей"
  local missing=()
  for cmd in sed curl; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    fail "Не найдены: ${missing[*]}"
    exit 1
  fi
  ok "Все зависимости доступны"

  if [[ "$USE_DOCKER" == "y" ]] && ! command -v docker &>/dev/null; then
    warn "Docker не найден. Будут сгенерированы только конфиги (без docker-compose)."
    USE_DOCKER="n"
  fi
}

# ─── Prompt helpers ─────────────────────────────────────────────────
prompt_select() {
  local prompt="$1"
  shift
  local options=("$@")
  echo -e "\n${BOLD}${prompt}${NC}"
  for i in "${!options[@]}"; do
    echo "  $((i+1))) ${options[$i]}"
  done
  read -rp "  Выбор [1-${#options[@]}]: " choice
  echo "$choice"
}

prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  if [[ -n "$default" ]]; then
    read -rp "  $prompt [$default]: " val
    echo "${val:-$default}"
  else
    read -rp "  $prompt: " val
    echo "$val"
  fi
}

prompt_yesno() {
  local prompt="$1"
  local default="${2:-y}"
  local hint="Y/n"
  [[ "$default" == "n" ]] && hint="y/N"
  read -rp "  $prompt [$hint]: " val
  val="${val:-$default}"
  [[ "$val" =~ ^[YyДд] ]] && echo "y" || echo "n"
}

# ─── Step 1: LLM ────────────────────────────────────────────────────
ask_llm() {
  header "📦 [1/6] LLM Provider"

  if [[ -z "$LLM_PROVIDER" ]]; then
    local choice
    choice=$(prompt_select "Выберите LLM провайдер:" "Ollama (local)" "vLLM (GPU server)" "OpenAI-compatible API")
    case "$choice" in
      1) LLM_PROVIDER="ollama" ;;
      2) LLM_PROVIDER="vllm" ;;
      3) LLM_PROVIDER="openai-compatible" ;;
      *) LLM_PROVIDER="ollama" ;;
    esac
  fi

  case "$LLM_PROVIDER" in
    ollama)
      LLM_API_FORMAT="openai-completions"
      LLM_API_KEY="ollama"
      if [[ -z "$LLM_BASE_URL" ]]; then
        LLM_BASE_URL=$(prompt_input "URL Ollama" "http://localhost:11434/v1")
      fi
      if [[ -z "$LLM_MODEL_ID" ]]; then
        LLM_MODEL_ID=$(prompt_input "Модель Ollama" "llama3.1:8b")
      fi
      LLM_MODEL_NAME="${LLM_PROVIDER} — ${LLM_MODEL_ID}"
      ;;
    vllm)
      LLM_API_FORMAT="openai-completions"
      if [[ -z "$LLM_BASE_URL" ]]; then
        LLM_BASE_URL=$(prompt_input "URL vLLM" "http://localhost:8000/v1")
      fi
      if [[ -z "$LLM_API_KEY" || "$LLM_API_KEY" == "ollama" ]]; then
        LLM_API_KEY=$(prompt_input "API Key (или 'none')" "none")
      fi
      if [[ -z "$LLM_MODEL_ID" ]]; then
        LLM_MODEL_ID=$(prompt_input "Модель" "meta-llama/Llama-3.1-8B-Instruct")
      fi
      LLM_MODEL_NAME="vLLM — ${LLM_MODEL_ID}"
      ;;
    openai-compatible)
      LLM_API_FORMAT="openai-completions"
      if [[ -z "$LLM_BASE_URL" ]]; then
        LLM_BASE_URL=$(prompt_input "URL API endpoint" "http://localhost:8080/v1")
      fi
      if [[ -z "$LLM_API_KEY" || "$LLM_API_KEY" == "ollama" ]]; then
        LLM_API_KEY=$(prompt_input "API Key" "")
      fi
      if [[ -z "$LLM_MODEL_ID" ]]; then
        LLM_MODEL_ID=$(prompt_input "ID модели" "default")
      fi
      LLM_MODEL_NAME="OpenAI-compatible — ${LLM_MODEL_ID}"
      ;;
  esac

  ok "LLM: ${LLM_MODEL_NAME} → ${LLM_BASE_URL}"
}

# ─── Step 2: Tool Policy ───────────────────────────────────────────
ask_policy() {
  header "🔒 [2/6] Tool Policy (уровень строгости)"

  if [[ "$TOOL_POLICY" != "strict" && "$TOOL_POLICY" != "standard" && "$TOOL_POLICY" != "sandboxed" ]]; then
    local choice
    choice=$(prompt_select "Выберите профиль:" \
      "Strict — минимум инструментов, максимальный контроль" \
      "Standard — баланс безопасности и функциональности" \
      "Sandboxed — exec разрешён, web_fetch для внутренних доменов")
    case "$choice" in
      1) TOOL_POLICY="strict" ;;
      2) TOOL_POLICY="standard" ;;
      3) TOOL_POLICY="sandboxed" ;;
      *) TOOL_POLICY="strict" ;;
    esac
  fi

  local desc=""
  case "$TOOL_POLICY" in
    strict)    desc="только read + memory. Для: юристы, финансы, HR" ;;
    standard)  desc="read/write/exec в sandbox. Для: разработчики" ;;
    sandboxed) desc="exec + web_fetch для внутренних. Для: CI/CD" ;;
  esac
  ok "Профиль: ${TOOL_POLICY} (${desc})"
}

# ─── Step 3: Compliance ────────────────────────────────────────────
ask_compliance() {
  header "📋 [3/6] Compliance Logging"

  if [[ "$COMPLIANCE_ENABLED" != "y" ]]; then
    COMPLIANCE_ENABLED=$(prompt_yesno "Отправлять логи на compliance-сервер?" "n")
  fi

  if [[ "$COMPLIANCE_ENABLED" == "y" && -z "$COMPLIANCE_URL" ]]; then
    COMPLIANCE_URL=$(prompt_input "URL compliance-сервера" "http://compliance.local:8080")
  fi

  if [[ "$COMPLIANCE_ENABLED" == "y" ]]; then
    ok "Compliance: ${COMPLIANCE_URL}"
  else
    info "Compliance: пропущен (необязательно)"
  fi
}

# ─── Step 4: Kill Switch ───────────────────────────────────────────
ask_killswitch() {
  header "🔴 [4/6] Kill Switch"

  if [[ "$KILLSWITCH_ENABLED" != "n" ]]; then
    KILLSWITCH_ENABLED=$(prompt_yesno "Настроить Kill Switch watchdog?" "y")
  fi

  if [[ "$KILLSWITCH_ENABLED" == "y" ]]; then
    DASHBOARD_PORT=$(prompt_input "Порт dashboard" "$DASHBOARD_PORT")
    ok "Kill Switch: watchdog + dashboard на :${DASHBOARD_PORT}"
  else
    info "Kill Switch: пропущен"
  fi
}

# ─── Step 5: Auth ───────────────────────────────────────────────────
ask_auth() {
  header "🔑 [5/6] Аутентификация"

  if [[ "$AUTH_METHOD" != "token" && "$AUTH_METHOD" != "none" ]]; then
    local choice
    choice=$(prompt_select "Способ аутентификации:" \
      "API-токен (рекомендуется)" \
      "Без аутентификации (ТОЛЬКО для тестов!)")
    case "$choice" in
      1) AUTH_METHOD="token" ;;
      2) AUTH_METHOD="none" ;;
      *) AUTH_METHOD="token" ;;
    esac
  fi

  if [[ "$AUTH_METHOD" == "none" ]]; then
    warn "БЕЗ аутентификации! Только для тестов."
  else
    ok "Auth: API-токен"
  fi
}

# ─── Step 6: Docker & Ports ────────────────────────────────────────
ask_docker() {
  header "🐳 [6/6] Docker & Сеть"

  GATEWAY_PORT=$(prompt_input "Порт Gateway" "$GATEWAY_PORT")
  TIMEZONE=$(prompt_input "Часовой пояс" "$TIMEZONE")

  ok "Порт: ${GATEWAY_PORT}, TZ: ${TIMEZONE}"
}

# ─── Template engine ───────────────────────────────────────────────
render_template() {
  local template_file="$1"
  local output_file="$2"

  local content
  content=$(cat "$template_file")

  # Timestamp
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S %Z')

  # Provider ID for config (use as-is, lowercase)
  local provider_id="${LLM_PROVIDER}"

  # Sandbox config
  local sandbox_config=""
  if [[ "$TOOL_POLICY" == "standard" || "$TOOL_POLICY" == "sandboxed" ]]; then
    sandbox_config='sandbox: { mode: "require" },'
  fi

  # Auth config block
  local auth_config=""
  case "$AUTH_METHOD" in
    token)
      auth_config='mode: "token",'
      ;;
    none)
      auth_config='mode: "none",'
      ;;
  esac

  # Trusted proxies
  local trusted_proxies_config=""
  trusted_proxies_config='trustedProxies: ["127.0.0.1"],'

  # Allowed origins (empty by default)
  local allowed_origins=""

  # Compliance config
  local compliance_config=""
  if [[ "$COMPLIANCE_ENABLED" == "y" ]]; then
    compliance_config="compliance: { enabled: true, endpoint: \"${COMPLIANCE_URL}\" },"
  fi

  # Docker-specific blocks
  local ollama_service=""
  local gateway_depends_on=""
  local killswitch_service=""
  local ollama_volume=""

  if [[ "$LLM_PROVIDER" == "ollama" && "$USE_DOCKER" == "y" ]]; then
    ollama_service=$(cat <<'OLLAMA'
  ollama:
    image: ollama/ollama:latest
    container_name: ollama-enterprise
    restart: unless-stopped
    volumes:
      - ollama-data:/root/.ollama
    networks:
      - enterprise-internal
    environment:
      - OLLAMA_HOST=0.0.0.0:11434
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: ${OLLAMA_MEMORY_LIMIT:-8G}
OLLAMA
    )
    gateway_depends_on='      ollama:
        condition: service_healthy'
    ollama_volume="ollama-data:"
  fi

  if [[ "$KILLSWITCH_ENABLED" == "y" && "$USE_DOCKER" == "y" ]]; then
    killswitch_service=$(cat <<KS
  watchdog:
    build: ../kill-switch/watchdog
    container_name: kill-switch-watchdog
    restart: unless-stopped
    environment:
      - TZ=${TZ:-${TIMEZONE}}
    volumes:
      - kill-switch-logs:/var/log/kill-switch
    networks:
      - enterprise-internal
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:5000/api/status')"]
      interval: 30s
      timeout: 5s
      retries: 3

  dashboard:
    image: nginx:alpine
    container_name: kill-switch-dashboard
    restart: unless-stopped
    ports:
      - "${DASHBOARD_PORT:-${DASHBOARD_PORT}}:8080"
    volumes:
      - ../kill-switch/dashboard:/usr/share/nginx/html:ro
    depends_on:
      - watchdog
    networks:
      - enterprise-internal
KS
    )
  fi

  # Internal domains for sandboxed
  local internal_domain_1="internal.corp.local"
  local additional_domains=""
  if [[ "$TOOL_POLICY" == "sandboxed" ]]; then
    if [[ "$NON_INTERACTIVE" == "false" ]]; then
      internal_domain_1=$(prompt_input "Внутренний домен #1" "internal.corp.local")
      local more
      more=$(prompt_yesno "Добавить ещё домены?" "n")
      if [[ "$more" == "y" ]]; then
        additional_domains=$(prompt_input "Дополнительные домены (через запятую, с '- ' перед каждым)")
      fi
    fi
  fi

  # Tool policy file path
  local tool_policy_file="tool-policy.yaml"

  # Do the replacements
  content="${content//\{\{TIMESTAMP\}\}/$ts}"
  content="${content//\{\{LLM_PROVIDER_ID\}\}/$provider_id}"
  content="${content//\{\{LLM_BASE_URL\}\}/$LLM_BASE_URL}"
  content="${content//\{\{LLM_API_KEY\}\}/$LLM_API_KEY}"
  content="${content//\{\{LLM_API_FORMAT\}\}/$LLM_API_FORMAT}"
  content="${content//\{\{LLM_MODEL_ID\}\}/$LLM_MODEL_ID}"
  content="${content//\{\{LLM_MODEL_NAME\}\}/$LLM_MODEL_NAME}"
  content="${content//\{\{LLM_REASONING\}\}/$LLM_REASONING}"
  content="${content//\{\{LLM_CONTEXT_WINDOW\}\}/$LLM_CONTEXT_WINDOW}"
  content="${content//\{\{LLM_MAX_TOKENS\}\}/$LLM_MAX_TOKENS}"
  content="${content//\{\{SANDBOX_CONFIG\}\}/$sandbox_config}"
  content="${content//\{\{GATEWAY_BIND\}\}/$GATEWAY_BIND}"
  content="${content//\{\{GATEWAY_PORT\}\}/$GATEWAY_PORT}"
  content="${content//\{\{TRUSTED_PROXIES_CONFIG\}\}/$trusted_proxies_config}"
  content="${content//\{\{AUTH_CONFIG\}\}/$auth_config}"
  content="${content//\{\{ALLOWED_ORIGINS\}\}/$allowed_origins}"
  content="${content//\{\{TOOL_POLICY_FILE\}\}/$tool_policy_file}"
  content="${content//\{\{COMPLIANCE_CONFIG\}\}/$compliance_config}"
  content="${content//\{\{TIMEZONE\}\}/$TIMEZONE}"
  content="${content//\{\{OLLAMA_SERVICE\}\}/$ollama_service}"
  content="${content//\{\{GATEWAY_DEPENDS_ON\}\}/$gateway_depends_on}"
  content="${content//\{\{KILLSWITCH_SERVICE\}\}/$killswitch_service}"
  content="${content//\{\{OLLAMA_VOLUME\}\}/$ollama_volume}"
  content="${content//\{\{DASHBOARD_PORT\}\}/$DASHBOARD_PORT}"
  content="${content//\{\{INTERNAL_DOMAIN_1\}\}/$internal_domain_1}"
  content="${content//\{\{ADDITIONAL_DOMAINS\}\}/$additional_domains}"

  # Also replace in env-specific vars
  content="${content//\{\{LLM_PROVIDER\}\}/$LLM_PROVIDER}"
  content="${content//\{\{KILLSWITCH_ENABLED\}\}/$KILLSWITCH_ENABLED}"
  content="${content//\{\{COMPLIANCE_ENABLED\}\}/$COMPLIANCE_ENABLED}"
  content="${content//\{\{COMPLIANCE_URL\}\}/$COMPLIANCE_URL}"

  echo "$content" > "$output_file"
}

# ─── Generate all configs ──────────────────────────────────────────
generate_configs() {
  header "⚙️ Генерация конфигурации"

  mkdir -p "$OUTPUT_DIR"

  # Gateway config
  render_template "$TEMPLATE_DIR/gateway.json5.template" "$OUTPUT_DIR/gateway.json5"
  ok "gateway.json5"

  # Tool policy
  render_template "$TEMPLATE_DIR/tool-policy-${TOOL_POLICY}.yaml.template" "$OUTPUT_DIR/tool-policy.yaml"
  ok "tool-policy.yaml (${TOOL_POLICY})"

  # Docker compose
  if [[ "$USE_DOCKER" == "y" ]]; then
    render_template "$TEMPLATE_DIR/docker-compose.yml.template" "$OUTPUT_DIR/docker-compose.yml"
    ok "docker-compose.yml"
  fi

  # .env
  render_template "$TEMPLATE_DIR/env.template" "$OUTPUT_DIR/.env"
  ok ".env"
}

# ─── Summary ────────────────────────────────────────────────────────
print_summary() {
  header "✅ Конфигурация создана!"
  echo -e "  ${BOLD}Папка:${NC} ${OUTPUT_DIR}/"
  echo ""
  echo -e "  ${CYAN}Файлы:${NC}"
  echo "  ├── gateway.json5          (конфиг Gateway)"
  echo "  ├── tool-policy.yaml       (tool policy: ${TOOL_POLICY})"
  if [[ "$USE_DOCKER" == "y" ]]; then
    echo "  ├── docker-compose.yml     (orchestration)"
  fi
  echo "  └── .env                   (переменные окружения)"
  echo ""
  echo -e "  ${CYAN}Параметры:${NC}"
  echo "  ├── LLM:         ${LLM_MODEL_NAME}"
  echo "  ├── Endpoint:    ${LLM_BASE_URL}"
  echo "  ├── Tool Policy: ${TOOL_POLICY}"
  echo "  ├── Auth:        ${AUTH_METHOD}"
  echo "  ├── Kill Switch: $([ "$KILLSWITCH_ENABLED" == "y" ] && echo "enabled (:${DASHBOARD_PORT})" || echo "disabled")"
  echo "  ├── Compliance:  $([ "$COMPLIANCE_ENABLED" == "y" ] && echo "$COMPLIANCE_URL" || echo "disabled")"
  echo "  ├── Gateway:     :${GATEWAY_PORT}"
  echo "  └── Timezone:    ${TIMEZONE}"
  echo ""

  if [[ "$USE_DOCKER" == "y" ]]; then
    echo -e "  ${GREEN}${BOLD}Запуск:${NC}"
    echo -e "  ${BOLD}cd ${OUTPUT_DIR} && docker compose up -d${NC}"
    echo ""
    echo -e "  ${CYAN}Проверка:${NC}"
    echo "  docker compose ps"
    echo "  curl http://localhost:${GATEWAY_PORT}/healthz"
    if [[ "$KILLSWITCH_ENABLED" == "y" ]]; then
      echo ""
      echo -e "  ${CYAN}Kill Switch Dashboard:${NC}"
      echo "  http://localhost:${DASHBOARD_PORT}"
    fi
  else
    echo -e "  ${GREEN}${BOLD}Запуск (без Docker):${NC}"
    echo -e "  ${BOLD}openclaw gateway --config ${OUTPUT_DIR}/gateway.json5${NC}"
  fi

  echo ""
  echo -e "  ${CYAN}Валидация:${NC}"
  echo -e "  ${BOLD}${SCRIPT_DIR}/validate.sh ${OUTPUT_DIR}/${NC}"
}

# ─── Main ───────────────────────────────────────────────────────────
main() {
  echo -e "\n${BOLD}${BLUE}🏠 OpenClaw Enterprise Setup Wizard${NC}\n"

  check_deps

  if [[ "$NON_INTERACTIVE" == "false" ]]; then
    ask_llm
    ask_policy
    ask_compliance
    ask_killswitch
    ask_auth
    ask_docker
  fi

  generate_configs
  print_summary
}

main "$@"
