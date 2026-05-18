# OpenClaw Enterprise Air-Gap — Deployment Guide

> Пошаговая инструкция: от подготовки хоста до первого запроса.

---

## Быстрый старт (для теста)

### Вариант A: Без Docker (Windows/macOS/Linux)

```bash
# 1. Установить Ollama
# Windows: скачай с https://ollama.com/download
# macOS:   brew install ollama
# Linux:   curl -fsSL https://ollama.com/install.sh | sh

# 2. Запустить Ollama и скачать модель
ollama serve
ollama pull llama3.1:8b

# 3. Скопировать конфиг
cp docs/enterprise/airgap-baseline.json5 ~/.openclaw/openclaw.json

# 4. Для теста БЕЗ прокси — временно переключить auth:
# В openclaw.json заменить:
#   "auth": { "mode": "trusted-proxy", ... }
# на:
#   "auth": { "mode": "token" }
# И задать токен:
export OPENCLAW_GATEWAY_TOKEN=my-test-token

# 5. Запустить Gateway
openclaw gateway --bind loopback

# 6. Открыть Web UI
# http://localhost:18789
```

### Вариант B: Docker Compose (рекомендуется для production)

```bash
# 1. Подготовить .env
cp docs/enterprise/.env.example .env
# Отредактировать .env — заполнить плейсхолдеры

# 2. Подготовить CA сертификаты (если есть внутренний CA)
mkdir -p certs
cp /path/to/company-ca.pem certs/ca-certificates.pem

# 3. Собрать образ
docker build -t openclaw:local .

# 4. Запустить
docker compose -f docker-compose.airgap.yml up -d

# 5. Проверить статус
docker compose -f docker-compose.airgap.yml ps
docker compose -f docker-compose.airgap.yml logs -f openclaw-gateway
```

---

## Production Setup (с reverse proxy + SSO)

### Шаг 1: Reverse Proxy (nginx + Keycloak/Authentik)

```nginx
# /etc/nginx/conf.d/openclaw.conf
server {
    listen 443 ssl;
    server_name openclaw.company.local;

    ssl_certificate /etc/nginx/ssl/openclaw.crt;
    ssl_certificate_key /etc/nginx/ssl/openclaw.key;

    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-User $remote_user;  # ← от SSO
    }
}
```

### Шаг 2: Включить trusted-proxy в конфиге

В `airgap-baseline.json5` убедиться что:
```json5
gateway: {
  auth: {
    mode: "trusted-proxy",
    trustedProxy: {
      userHeader: "X-Forwarded-User",
      requiredHeaders: ["X-Forwarded-For", "X-Forwarded-Proto"],
      allowUsers: ["user1@company.local", "user2@company.local"],
      allowLoopback: false,
    },
  },
  trustedProxies: ["IP_ПРОКСИ"],
  controlUi: {
    allowedOrigins: ["https://openclaw.company.local"],
  },
}
```

### Шаг 3: Firewall

```bash
# Egress deny-by-default (Linux)
iptables -P OUTPUT DROP
iptables -A OUTPUT -d 172.28.0.0/16 -j ACCEPT  # airgap-internal сеть
iptables -A OUTPUT -d 127.0.0.1 -j ACCEPT        # loopback
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT   # DNS (внутренний)
# Добавить нужные внутренние endpoints по whitelist
```

### Шаг 4: CA сертификаты

```bash
# Linux: системный CA
sudo cp company-ca.pem /usr/local/share/ca-certificates/
sudo update-ca-certificates

# Docker: через .env
CA_CERT_PATH=/path/to/company-ca.pem

# Windows:
set NODE_EXTRA_CA_CERTS=C:\certs\ca-certificates.pem

# macOS:
export NODE_EXTRA_CA_CERTS=/etc/ssl/company-ca.pem
```

### Шаг 5: Security Audit

```bash
# После развертывания — обязательно запустить
openclaw security audit
openclaw security audit --deep

# Проверить статус
openclaw doctor
openclaw status
```

---

## Проверка всех 8 функций

| # | Функция | Как проверить |
|---|---------|---------------|
| 1 | Внутренний LLM | `curl http://localhost:11434/api/tags` — модель доступна |
| 2 | Trusted-proxy | Запрос без заголовка X-Forwarded-User → 401/403 |
| 3 | Network exposure | `netstat -an | grep 18789` — только loopback |
| 4 | Security audit | `openclaw security audit` — passed |
| 5 | Tools ограничения | В Web UI попросить "поищи в интернете" → отказ |
| 6 | Внутренние каналы | Конфиг: все внешние channels enabled: false |
| 7 | CA сертификаты | `curl https://internal-api.company.local` — без ошибки |
| 8 | Read-only | В Web UI попросить "создай файл test.txt" → отказ |

---

## Troubleshooting

### "Connection refused" на порту 18789
- Gateway не запущен → `openclaw gateway --bind loopback`
- Проверить: `curl http://localhost:18789/healthz`

### Ollama недоступна из Docker
- В docker-compose: `extra_hosts: ["host.docker.internal:host-gateway"]`
- В конфиге: `baseUrl: "http://host.docker.internal:11434/v1"`

### WebSocket 1008 unauthorized
- Trusted-proxy mode требует заголовки от прокси
- Для теста без прокси: переключить на `auth: { mode: "token" }`

### CA сертификаты не работают
- Проверить путь: `ls $NODE_EXTRA_CA_CERTS`
- В Docker: проверить volume mount в docker-compose

### Tools не блокируются
- Проверить что конфиг загружен: `openclaw config get tools.deny`
- Проверить profile: `openclaw config get tools.profile`

---

## Откат к стандартному режиму

Если нужно вернуться к обычной работе:

```bash
# Удалить airgap конфиг
rm ~/.openclaw/openclaw.json

# Запустить onboarding заново
openclaw onboard

# или восстановить бэкап
cp ~/.openclaw/openclaw.json.backup ~/.openclaw/openclaw.json
```
