# OpenClaw Enterprise — Air-Gap Deployment Kit

> **Безопасное развёртывание OpenClaw в закрытом корпоративном контуре.**
> Прототип + инструкции + шаблоны для доработки под нужды предприятия.

---

<p align="center">
  <a href="docs/ENTERPRISE-AIRGAP-DEPLOY2.md"><img src="https://img.shields.io/badge/Docs-26_Sections-blue?style=for-the-badge" alt="Documentation"></a>
  <a href="kill-switch/"><img src="https://img.shields.io/badge/Kill_Switch-Prototype-green?style=for-the-badge" alt="Kill Switch"></a>
  <a href="configs/enterprise-tool-profiles/"><img src="https://img.shields.io/badge/Tool_Profiles-3_Templates-orange?style=for-the-badge" alt="Tool Profiles"></a>
  <a href="compliance/"><img src="https://img.shields.io/badge/Compliance_Log_Shipper-Prototype-purple?style=for-the-badge" alt="Compliance"></a>
  <img src="https://img.shields.io/badge/Tests-27%2F27_passing-brightgreen?style=for-the-badge" alt="Tests">
</p>

---

## Что это

Набор шаблонов, прототипов и документации для развёртывания [OpenClaw](https://github.com/openclaw/openclaw) в enterprise-окружении с жёсткими ограничениями безопасности:

- **Без доступа к публичному интернету** (air-gap / закрытый контур)
- **Без облачных SaaS-провайдеров** (модели — self-hosted: Ollama, vLLM)
- **С полным аудитом** действий агента и пользователя
- **С Kill Switch** — аварийная остановка для ИБ-отдела

## Проблема

OpenClaw по умолчанию — персональный ассистент с широкими возможностями: интернет-поиск, выполнение команд, браузер. Для корпоративного использования это **неприемлемо** — нужны жёсткие ограничения.

## Решение

Этот репозиторий — **отправная точка** для enterprise-развёртывания. Не готовый продукт, а база с тремя ключевыми компонентами:

### 🔴 Kill Switch — аварийная остановка агентов
- Watchdog (Python + Flask) — опрос Gateway, мягкая/жёсткая остановка
- Dashboard — веб-пульт для ИБ-отдела
- 27 юнит-тестов, все проходят
- Устанавливается на **отдельную машину**
- [→ Документация](kill-switch/README.md)

### 🟠 Tool Policy — изоляция инструментов
- 3 готовых профиля: Strict / Standard / Sandboxed
- Deny-all по умолчанию, whitelist только нужного
- Запрет web_search, web_fetch, exec, browser
- [→ Шаблоны YAML](configs/enterprise-tool-profiles/)

### 🟣 Compliance Logging — чёрный ящик
- Log Shipper — отправка логов на отдельный сервер комплаенс
- Стандартный формат аудита (JSON schema)
- API-контракт для предприятия (POST /api/v1/audit/batch)
- [→ Прототип](compliance/README.md)

## Архитектура

```text
[Сотрудник] → [Reverse Proxy + SSO] → [OpenClaw Gateway] → [Внутренняя LLM]
                                         ↓
                                    [Внутренние API]
                                         ↓
                              [Log Shipper] → [Compliance Server]

[ИБ-отдел] → [Kill Switch Dashboard] → [Watchdog] → [Gateway API]
              (отдельная машина)
```

## Быстрый старт

```bash
git clone https://github.com/dmantipinai-hash/openclaw-business.git
cd openclaw-business

# Полная документация — 26 секций
cat docs/ENTERPRISE-AIRGAP-DEPLOY2.md

# Приветствие для сотрудников (положить в workspace агента)
cat workspace/ENTERPRISE-WELCOME.md
```

## Для кого

- **Предприятия** с закрытым контуром (банки, госсектор, промышленность)
- **ИБ-отделы** — Kill Switch, tool policy, compliance logging
- **Комплаенс** — полный аудит действий агента
- **DevOps-инженеры** — развёртывание и настройка

## Структура репозитория

```text
├── docs/
│   └── ENTERPRISE-AIRGAP-DEPLOY2.md   ← Основной документ (26 секций)
├── kill-switch/                         ← Kill Switch (watchdog + dashboard + тесты)
│   ├── watchdog/
│   ├── dashboard/
│   └── README.md
├── compliance/                          ← Compliance Logging (log shipper)
│   ├── log-shipper.py
│   ├── audit-format.json
│   └── README.md
├── configs/
│   └── enterprise-tool-profiles/        ← 3 профиля tool policy (YAML)
├── workspace/
│   └── ENTERPRISE-WELCOME.md            ← Приветствие для сотрудника
└── docker-compose.airgap.yml
```

## Важно понимать

Это **прототип** — базовая структура для доработки. Без реального предприятия с конкретными требованиями невозможно сделать готовое решение.

**Что есть:** шаблоны, инструкции, прототипы, тесты, документация.
**Чего нет:** готового compliance-сервера, интеграций с конкретными системами, production-тестирования.

Каждая организация уникальна: своя сеть, свои сервисы, свои требования безопасности. Этот репозиторий — **отправная точка**, а не финальный продукт.

## Ключевые слова

`openclaw` `enterprise` `airgap` `air-gap` `compliance` `security` `kill-switch` `tool-policy` `sandbox` `audit` `logging` `self-hosted` `ollama` `vllm` `closed-network` `offline` `hardened` `rbac` `dlp` `corporate` `intrusion` `network-isolation` `zero-trust`

---

## Attribution

This project is based on [OpenClaw](https://github.com/openclaw/openclaw) by Peter Steinberger.
Original project: https://github.com/openclaw/openclaw
License: MIT (see [LICENSE](LICENSE))

Enterprise deployment kit, Kill Switch, Tool Policy profiles, and Compliance Logging are original additions and not part of the upstream OpenClaw project.
