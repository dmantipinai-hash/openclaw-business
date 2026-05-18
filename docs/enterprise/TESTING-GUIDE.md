# OpenClaw Enterprise Air-Gap — Testing Guide

> Как протестировать все 8 функций на ноутбуке БЕЗ Docker.

---

## Подготовка (5 минут)

### 1. Установить Ollama

**Windows:**
```
Скачай с https://ollama.com/download/windows
Установи → Ollama запустится в трее
```

**macOS:**
```bash
brew install ollama
ollama serve
```

**Linux (WSL2):**
```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### 2. Скачать модель
```bash
ollama pull llama3.1:8b
# Проверить:
ollama list
```

### 3. Установить OpenClaw (если не установлен)
```bash
npm install -g openclaw
```

### 4. Сделать бэкап текущего конфига
```bash
# macOS/Linux:
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.backup

# Windows (PowerShell):
Copy-Item "$env:USERPROFILE\.openclaw\openclaw.json" "$env:USERPROFILE\.openclaw\openclaw.json.backup"
```

### 5. Скопировать airgap конфиг
```bash
# macOS/Linux:
cp docs/enterprise/airgap-baseline.json5 ~/.openclaw/openclaw.json

# Windows (PowerShell):
Copy-Item "docs\enterprise\airgap-baseline.json5" "$env:USERPROFILE\.openclaw\openclaw.json"
```

### 6. Переключить auth для теста БЕЗ прокси

В `~/.openclaw/openclaw.json` заменить:
```json5
// ЗАМЕНИТЬ:
auth: {
  mode: "trusted-proxy",
  trustedProxy: { ... }
}

// НА:
auth: {
  mode: "token"
}
```

И задать токен:
```bash
# macOS/Linux:
export OPENCLAW_GATEWAY_TOKEN=test-token-123

# Windows (PowerShell):
$env:OPENCLAW_GATEWAY_TOKEN = "test-token-123"
```

---

## Запуск

```bash
openclaw gateway --bind loopback
```

Открыть в браузере: http://localhost:18789

---

## Тестирование 8 функций

### ✅ ФИЧА 1: Внутренний LLM

**Что проверить:** Gateway использует ТОЛЬКО Ollama, не звонит во внешние API.

**Как:**
1. Открыть Web UI → задать вопрос "Привет, ты работаешь?"
2. Ожидаемый ответ: агент отвечает
3. Проверить логи: НЕ должно быть запросов к api.openai.com / api.anthropic.com

```bash
# Проверить что Ollama работает:
curl http://localhost:11434/api/tags
```

### ✅ ФИЧА 2: Trusted-proxy (токен для теста)

**Что проверить:** Без токена/заголовка — доступ закрыт.

**Как:**
1. Открыть http://localhost:18789 без токена → должен запросить авторизацию
2. С токеном (в URL: ?token=test-token-123) → доступ разрешён

### ✅ ФИЧА 3: Network exposure

**Что проверить:** Gateway слушает ТОЛЬКО на localhost.

**Как:**
```bash
# macOS/Linux:
netstat -an | grep 18789
# Ожидаемый вывод: 127.0.0.1:18789 (только localhost)

# Windows (PowerShell):
netstat -an | Select-String "18789"
# Ожидаемый вывод: 127.0.0.1:18789

# С другого компьютера в сети:
curl http://IP_ВАШЕГО_НОУТБУКА:18789/healthz
# Ожидаемый результат: Connection refused
```

### ✅ ФИЧА 4: Security audit

**Что проверить:** Аудит не находит критических проблем.

**Как:**
```bash
openclaw security audit
openclaw security audit --deep
openclaw doctor
```

### ✅ ФИЧА 5: Отключение опасных tools

**Что проверить:** Агент НЕ может: искать в интернете, открывать браузер, выполнять команды.

**Как:**
В Web UI попросить:
- "Найди в интернете курс доллара" → **ОТКАЗ** (web_search заблокирован)
- "Открой сайт google.com" → **ОТКАЗ** (web_fetch заблокирован)
- "Создай файл test.txt" → **ОТКАЗ** (write заблокирован)
- "Выполни команду ls" → **ОТКАЗ** (exec заблокирован)
- "Запусти субагента" → **ОТКАЗ** (sessions_spawn заблокирован)

### ✅ ФИЧА 6: Только внутренние каналы

**Что проверить:** В конфиге все внешние каналы выключены.

**Как:**
```bash
openclaw config get channels.telegram
# Ожидаемый вывод: enabled: false

openclaw config get channels.whatsapp
# Ожидаемый вывод: enabled: false

openclaw config get channels.webchat
# Ожидаемый вывод: enabled: true
```

### ✅ ФИЧА 7: CA сертификаты

**Что проверить:** Переменная NODE_EXTRA_CA_CERTS принята.

**Как:**
```bash
# macOS/Linux:
echo $NODE_EXTRA_CA_CERTS

# Windows:
echo $env:NODE_EXTRA_CA_CERTS

# Для реального теста нужен внутренний CA файл
# Создать тестовый:
# mkdir -p certs && touch certs/ca-certificates.pem
# export NODE_EXTRA_CA_CERTS=$(pwd)/certs/ca-certificates.pem
```

### ✅ ФИЧА 8: Read-only режим

**Что проверить:** Агент может ТОЛЬКО читать, не может писать.

**Как:**
В Web UI попросить:
- "Прочитай файл openclaw.json" → **УСПЕХ** (read разрешён)
- "Покажи текущие конфиги" → **УСПЕХ** (session_status разрешён)
- "Создай файл hello.txt с текстом 'привет'" → **ОТКАЗ** (write заблокирован)
- "Отредактируй файл openclaw.json" → **ОТКАЗ** (edit заблокирован)

---

## Откат после теста

```bash
# Вернуть стандартный конфиг:
cp ~/.openclaw/openclaw.json.backup ~/.openclaw/openclaw.json

# Убрать токен:
unset OPENCLAW_GATEWAY_TOKEN        # macOS/Linux
Remove-Item Env:OPENCLAW_GATEWAY_TOKEN  # Windows

# Перезапустить:
openclaw gateway restart
```

---

## Чеклист перед показом заказчику

- [ ] Ollama запущена и модель загружена
- [ ] Конфиг airgap-baseline.json5 скопирован
- [ ] Auth переключен на token (для теста без прокси)
- [ ] Gateway запущен и отвечает на healthz
- [ ] Web UI открывается в браузере
- [ ] Все 8 тестов пройдены
- [ ] Логи проверены — нет обращений к внешним API
