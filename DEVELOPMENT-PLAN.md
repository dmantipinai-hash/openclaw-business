# OpenClaw Business — План развития

> ⚠️ **Этот документ — рабочий план для внутреннего использования.**
> Перед публикацией репозитория: либо удалить, либо переписать как публичную документацию (ROADMAP.md).
> Создан: 2026-05-23

---

## Цель проекта

**Обучение + портфолио.** Если в результате работодатель найдётся — супер.

Фокус: enterprise-развёртывание OpenClaw (air-gap, безопасность, compliance).
Рыночный контекст: 89% AI-проектов не доходят до production (Deloitte), главная причина — нет governance. Проекты с governance в 12x чаще доходят до production (Databricks).

---

## ✅ Этап 1: Onboarding Wizard (`setup-wizard/`)

**Проблема:** Скачал репозиторий → документация 26 секций → утонул. Нет пошагового мастера.

**Цель:** 3 команды до работающей системы.

### 1.1 Интерактивный `setup.sh`

**Путь:** `setup-wizard/setup.sh`

Скрипт задаёт 5-7 вопросов и генерирует все нужные конфиги:

```
./setup.sh

🏠 OpenClaw Enterprise Setup Wizard

[1/6] LLM Provider
  1) Ollama (local)
  2) vLLM (GPU server)
  3) OpenAI-compatible API
  Выбор: 1
  URL Ollama: [http://localhost:11434]

[2/6] Tool Policy (уровень строгости)
  1) Strict — минимум инструментов, максимальный контроль
  2) Standard — баланс безопасности и функциональности
  3) Custom — настроить вручную
  Выбор: 1

[3/6] Compliance Logging
  Отправлять логи на compliance-сервер? [y/N]: y
  URL compliance-сервера: http://compliance.local:8080

[4/6] Kill Switch
  Настроить watchdog? [Y/n]: y
  Порт dashboard: [8081]

[5/6] Пользователи
  Способ аутентификации:
  1) Без аутентификации (только для тестов!)
  2) API-токен
  3) LDAP
  4) SAML (TODO)
  Выбор: 2

[6/6] Docker
  Использовать Docker? [Y/n]: y
  Порт Gateway: [3000]

✅ Конфигурация создана в ./output/
   - gateway.json
   - tool-policy.yaml
   - docker-compose.yml
   - .env

Запуск: cd output && docker-compose up -d
```

**Реализация:**
- Bash-скрипт с `select` и `read`
- Цветной вывод (ANSI escape codes)
- Проверка зависимостей (docker, curl) перед запуском
- Поддержка `--non-interactive` с флагами для CI

**Флаги для CI:**
```bash
./setup.sh --non-interactive \
  --llm ollama \
  --llm-url http://localhost:11434 \
  --policy strict \
  --compliance http://compliance.local:8080 \
  --killswitch 8081 \
  --auth token \
  --docker
```

### 1.2 Шаблоны конфигов

**Путь:** `setup-wizard/templates/`

Файлы-шаблоны с плейсхолдерами вида `{{VARIABLE}}`:

- **`gateway.json.template`** — конфиг Gateway (модель, порт, SSO, memory)
- **`tool-policy.yaml.template`** — tool policy на основе выбранного профиля
- **`docker-compose.yml.template`** — compose-файл (gateway + watchdog + log-shipper)
- **`.env.template`** — переменные окружения

Шаблонизатор — простой `sed` в bash. Без внешних зависимостей.

**Пример `gateway.json.template`:**
```json
{
  "gateway": {
    "port": {{GATEWAY_PORT}},
    "host": "0.0.0.0"
  },
  "models": {
    "default": "{{LLM_PROVIDER}}/{{LLM_MODEL}}"
  },
  "tools": {
    "policy": "{{TOOL_POLICY_FILE}}"
  },
  "auth": {
    "method": "{{AUTH_METHOD}}"
  }
}
```

### 1.3 Валидация конфигурации

**Путь:** `setup-wizard/validate.sh`

Запускается после генерации (или отдельно):

```bash
./validate.sh ./output/
```

**Проверки:**
- `gateway.json` — валидный JSON, все обязательные поля заполнены
- `tool-policy.yaml` — валидный YAML, нет запрещённых инструментов в whitelist
- `docker-compose.yml` — валидный compose, порты не конфликтуют
- LLM endpoint — доступен (curl проверка)
- Kill Switch — watchdog отвечает
- Compliance — endpoint доступен (если настроен)
- Нет секретов в конфигах (grep на API key patterns)

**Вывод:**
```
🔍 Validating configuration...

✅ gateway.json — valid
✅ tool-policy.yaml — valid (strict profile, 12 tools blocked)
✅ docker-compose.yml — valid
✅ LLM endpoint http://localhost:11434 — responding
✅ Kill Switch :8081 — responding
⚠️ Compliance http://compliance.local:8080 — not reachable (optional)
✅ No secrets found in config files

Score: 5/6 — ready to deploy
```

### 1.4 Обновить README

Добавить секцию «Quick Start» в начало README.md:

```markdown
## Quick Start (3 команды)

```bash
git clone https://github.com/dmantipinai-hash/openclaw-business.git
cd openclaw-business/setup-wizard
./setup.sh
cd output && docker-compose up -d
```

Готово. OpenClaw enterprise работает на http://localhost:3000
```

### Порядок работы (Этап 1)

| Сессия | Задачи | Время |
|--------|--------|-------|
| 1 | Шаблоны конфигов (1.2) — создать все template-файлы | 1-1.5ч |
| 2 | setup.sh (1.1) — интерактивный опрос + генерация | 1.5-2ч |
| 3 | validate.sh (1.3) + обновить README (1.4) + тестирование | 1.5-2ч |

---

## ✅ Этап 4: Security Testing Suite (`security-tests/`)

**Проблема:** ИБ-отделу нужно *доказать* что конфигурация безопасна. Сейчас — только ручное чтение YAML.

**Цель:** Одна команда → отчёт для ИБ-отдела.

### 4.1 Чек-лист проверок

**Путь:** `security-tests/checks.yaml`

YAML-файл с описанием всех проверок:

```yaml
checks:
  - id: tool-policy-loaded
    category: tool_policy
    severity: critical
    description: "Tool policy загружена и содержит записи"
    test: "check_tool_policy_loaded"

  - id: no-internet-tools
    category: tool_policy
    severity: critical
    description: "Запрещены web_search, web_fetch, browser"
    test: "check_blocked_tools"
    params:
      blocked: ["web_search", "web_fetch", "browser_automation"]

  - id: no-exec-unrestricted
    category: tool_policy
    severity: high
    description: "exec не в unrestricted режиме"
    test: "check_exec_policy"

  - id: kill-switch-responding
    category: kill_switch
    severity: critical
    description: "Watchdog отвечает на healthcheck"
    test: "check_kill_switch"

  - id: kill-switch-can-stop
    category: kill_switch
    severity: critical
    description: "Watchdog может остановить агента"
    test: "check_kill_switch_stop"

  - id: no-secrets-in-config
    category: data_leak
    severity: critical
    description: "Нет API-ключей и паролей в конфиг-файлах"
    test: "check_no_secrets"

  - id: compliance-endpoint-reachable
    category: compliance
    severity: medium
    description: "Compliance-сервер доступен"
    test: "check_compliance_endpoint"

  - id: gateway-not-public
    category: network
    severity: critical
    description: "Gateway не доступен извне (binds to localhost/internal)"
    test: "check_gateway_binding"

  - id: docker-network-isolated
    category: network
    severity: high
    description: "Docker-сети изолированы (no host network)"
    test: "check_docker_network"
```

### 4.2 Раннер тестов

**Путь:** `security-tests/run-tests.sh` (bash) или `security-tests/run_tests.py` (python)

Читает `checks.yaml` → выполняет проверки → выводит результат.

**Архитектура:**
```
run-tests.sh
  → читает checks.yaml
  → вызывает функции из lib/checks/*.sh
  → собирает результаты
  → генерирует отчёт
```

Каждая проверка — отдельная функция в `lib/checks/`:
- `lib/checks/tool_policy.sh`
- `lib/checks/kill_switch.sh`
- `lib/checks/data_leak.sh`
- `lib/checks/network.sh`
- `lib/checks/compliance.sh`

### 4.3 Интеграция с Kill Switch

Автоматические тесты для watchdog:

- **Healthcheck** — GET `/health` → ожидаем 200
- **Agent list** — GET `/api/agents` → ожидаем JSON
- **Soft stop** — POST `/api/agents/{id}/soft-stop` → ожидаем 200
- **Hard stop** — POST `/api/agents/{id}/hard-stop` → ожидаем 200
- **Dashboard** — GET `:8081` → ожидаем HTML

Использует существующий Kill Switch из репозитория (`kill-switch/watchdog/`).

### 4.4 Генерация отчёта

**Форматы:** Markdown (по умолчанию) + JSON (для программного использования)

**Пример Markdown-отчёта:**

```markdown
# 🔐 Security Test Report

**Дата:** 2026-05-23 12:30 MSK
**Среда:** staging / production
**Профиль:** strict

## Результаты

| Статус | Проверка | Категория | Важность |
|--------|----------|-----------|----------|
| ✅ | Tool policy загружена | tool_policy | critical |
| ✅ | Интернет-инструменты заблокированы | tool_policy | critical |
| ✅ | exec ограничен | tool_policy | high |
| ✅ | Kill Switch отвечает | kill_switch | critical |
| ✅ | Kill Switch может остановить | kill_switch | critical |
| ✅ | Нет секретов в конфигах | data_leak | critical |
| ⚠️ | Compliance endpoint недоступен | compliance | medium |
| ✅ | Gateway не публичный | network | critical |
| ✅ | Docker-сети изолированы | network | high |

## Итого: 8/9 (89%)

**Критические:** 0 проблем ✅
**Высокие:** 0 проблем ✅
**Средние:** 1 предупреждение ⚠️

### Рекомендации

⚠️ **compliance-endpoint-reachable:** Compliance-сервер недоступен.
Если compliance logging не нужен — можно проигнорировать.
Если нужен — проверьте URL в .env и доступность сервера.
```

### 4.5 CI интеграция

**Путь:** `.github/workflows/security-tests.yml`

```yaml
name: Security Tests
on:
  push:
    paths:
      - 'configs/**'
      - 'security-tests/**'
      - 'kill-switch/**'
  pull_request:
  workflow_dispatch:
```

Запускается автоматически при изменении конфигов. Результат — в Checks tab на GitHub.

### Порядок работы (Этап 4)

| Сессия | Задачи | Время |
|--------|--------|-------|
| 4 | checks.yaml (4.1) + базовый раннер (4.2) — каркас + 3-4 проверки | 1.5-2ч |
| 5 | Интеграция Kill Switch (4.3) + ещё 2-3 проверки + отчёт (4.4) | 1.5-2ч |
| 6 | CI workflow (4.5) + полное тестирование всего | 1-1.5ч |

---

## 📋 Отложенные этапы (для рассмотрения)

### Этап 2: Dashboard — Мониторинг агентов в реальном времени

**Проблема:** Kill Switch — это «кнопка паники». Нужен нормальный мониторинг: кто, когда, какие модели использовал.

**Что делать:**
- Веб-страница (React или простой HTML+JS)
- API-эндпоинты на базе Kill Switch watchdog
- Метрики: активные сессии, токены по пользователям, топ инструментов, алерты
- Можно расширить существующий `kill-switch/dashboard/`

**Оценка:** 3-4 сессии

### Этап 3: Template Library — Отраслевые пресеты

**Проблема:** Каждая организация начинает с нуля, но у банков/заводов/госсектора похожие требования.

**Что делать:**
- `templates/banking.yaml` — жёсткий DLP, аудит каждого действия
- `templates/manufacturing.yaml` — интеграция с MES/ERP, read-only
- `templates/government.yaml` — ГОСТ-шифрование, ФСТЭК
- `templates/startup.yaml` — лояльный, базовый аудит
- Каждый пресет — готовый набор для setup.sh

**Оценка:** 2-3 сессии

### Этап 5: Docker Image — Один клик до работающей системы

**Проблема:** Сейчас нужно клонировать, настроить, собрать. Docker-образ снизит порог до 30 минут.

**Что делать:**
- `Dockerfile` с преднастроенным OpenClaw + enterprise-расширениями
- Публиковать в GitHub Container Registry (ghcr.io)
- Запуск одной командой: `docker run -e LLM_ENDPOINT=http://ollama:11434 ...`
- Версионирование: `openclaw-business/enterprise:2026.5`

**Оценка:** 2-3 сессии

---

## Общая оценка времени

| Этап | Сессии | Часы | Приоритет |
|------|--------|------|-----------|
| 1. Onboarding Wizard | 3 | 4-5.5ч | 🔴 Сейчас |
| 4. Security Testing | 3 | 4-5.5ч | 🔴 Сейчас |
| 2. Dashboard | 3-4 | 4-6ч | 🟡 Позже |
| 3. Template Library | 2-3 | 3-4ч | 🟡 Позже |
| 5. Docker Image | 2-3 | 3-4ч | 🟡 Позже |

---

_Документ создан Астрой. После завершения этапов 1 и 4 — удалить или переписать как ROADMAP.md._
