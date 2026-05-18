# OpenClaw Enterprise Air-Gap — Security Audit Checklist

> Запустить после каждого деплоя. Обязательный baseline для compliance.

---

## Перед запуском

```bash
# 1. Запустить аудит
openclaw security audit

# 2. Глубокий аудит
openclaw security audit --deep

# 3. Проверить здоровье
openclaw doctor
openclaw status
```

---

## Чеклист

### 🔴 Критично (должно быть OK перед запуском)

- [ ] **Auth включён** — `openclaw config get gateway.auth.mode` ≠ "none"
- [ ] **Bind = loopback** — Gateway не торчит в сеть
  ```bash
  openclaw config get gateway.bind
  # Ожидаемое: "loopback" или "lan" (если за proxy)
  ```
- [ ] **Нет внешних провайдеров** — в models.providers только ollama
  ```bash
  openclaw config get models.providers
  # НЕ должно быть: openai, anthropic, google, zai
  ```
- [ ] **Web tools отключены**
  ```bash
  openclaw config get tools.deny
  # Должно содержать: web_search, web_fetch, browser
  ```
- [ ] **Внешние каналы выключены**
  ```bash
  openclaw config get channels.telegram.enabled    # false
  openclaw config get channels.whatsapp.enabled    # false
  openclaw config get channels.discord.enabled     # false
  openclaw config get channels.signal.enabled      # false
  ```

### 🟡 Важно (проверить после запуска)

- [ ] **Токен/пароль задан** (если не trusted-proxy)
- [ ] **Trusted proxies настроены** (если trusted-proxy)
  ```bash
  openclaw config get gateway.trustedProxies
  ```
- [ ] **allowUsers не пустой** (если нужен доступ конкретных людей)
  ```bash
  openclaw config get gateway.auth.trustedProxy.allowUsers
  ```
- [ ] **Логирование включено**
  ```bash
  openclaw config get logging.redactSensitive
  # Ожидаемое: "tools" или "full"
  ```
- [ ] **CA сертификаты подключены** (если есть внутренний CA)
  ```bash
  echo $NODE_EXTRA_CA_CERTS
  # Не должно быть пустым
  ```

### 🟢 Периодически (раз в неделю)

- [ ] Запустить `openclaw security audit --deep`
- [ ] Проверить что нет новых external providers
- [ ] Проверить логи на попытки внешних подключений
- [ ] Проверить что deny-list инструментов не обойден
- [ ] Обновить подавления (suppressions) в security.audit если есть ложные срабатывания

---

## Результат аудита

Записать результаты в таблицу:

| Дата | `security audit` | `security audit --deep` | `doctor` | Комментарии |
|------|------------------|------------------------|----------|-------------|
| YYYY-MM-DD | ✅/❌ | ✅/❌ | ✅/❌ | ... |
