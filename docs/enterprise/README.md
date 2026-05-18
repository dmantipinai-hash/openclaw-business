# OpenClaw Enterprise Air-Gap

Артефакты для развёртывания OpenClaw в закрытом корпоративном контуре (air-gap).

## Файлы

| Файл | Назначение |
|------|------------|
| `airgap-baseline.json5` | Готовый конфиг — все 8 функций в одном файле, закомментированный |
| `DEPLOY-GUIDE.md` | Пошаговый гайд: тест без Docker → Docker → Production с SSO |
| `TESTING-GUIDE.md` | Как протестировать каждую из 8 функций на ноутбуке |
| `.env.example` | Шаблон переменных окружения для Docker |
| `TASK-WORKLOG.md` | Ход работы и покрытие функций |

## 8 функций

1. **Внутренний LLM** — Ollama вместо OpenAI/Anthropic
2. **Trusted-proxy + SSO** — auth через reverse proxy (Keycloak/Authentik)
3. **Network exposure** — bind loopback + изолированная Docker-сеть
4. **Security audit** — логирование + redaction + audit baseline
5. **Tools ограничения** — deny-by-default для опасных инструментов
6. **Внутренние каналы** — только Web UI, все внешние выключены
7. **CA сертификаты** — NODE_EXTRA_CA_CERTS для внутренних CA
8. **Read-only режим** — запрет записи/исполнения на старте

## Быстрый старт

```bash
# 1. Скопировать конфиг
cp docs/enterprise/airgap-baseline.json5 ~/.openclaw/openclaw.json

# 2. Для теста без прокси: переключить auth на token
# В openclaw.json: "mode": "token"
# export OPENCLAW_GATEWAY_TOKEN=my-token

# 3. Запустить Ollama
ollama pull llama3.1:8b
ollama serve

# 4. Запустить Gateway
openclaw gateway --bind loopback

# 5. Открыть http://localhost:18789
```

Подробнее: см. [TESTING-GUIDE.md](./TESTING-GUIDE.md)

## Production

```bash
cp docs/enterprise/.env.example .env
# Заполнить .env
docker compose -f docker-compose.airgap.yml up -d
```

Подробнее: см. [DEPLOY-GUIDE.md](./DEPLOY-GUIDE.md)

---

*Основной документ: [ENTERPRISE-AIRGAP-DEPLOY2.md](../ENTERPRISE-AIRGAP-DEPLOY2.md)*
