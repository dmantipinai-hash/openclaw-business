# Kill Switch — Аварийная остановка всех агентов

> ⚠️ **ВАЖНО:** Устанавливать на **ОТДЕЛЬНУЮ МАШИНУ**, не туда же где OpenClaw Gateway.
> Если Gateway зависнет — Kill Switch должен продолжать работать.

---

## Что это

Kill Switch — это простой веб-пульт для ИБ-отдела, который позволяет:

- **Одной кнопкой остановить** одного агента, группу или ВСЕХ
- **Немедленно** — даже если агент уже обрабатывает запрос от LLM
- **Из другого процесса** — не зависит от здоровья OpenClaw Gateway
- **Видеть всех запущенных агентов** на всех Gateway-хостах

---

## Архитектура

```
┌─────────────────────────────────────────────────┐
│  МАШИНА ИБ-ОТДЕЛА (этот компонент)              │
│                                                  │
│  ┌──────────────────┐   ┌────────────────────┐  │
│  │  Dashboard UI     │   │  Watchdog          │  │
│  │  (nginx static)   │──▶│  (Python/Node)     │  │
│  │  порт 8080        │   │  опрашивает Gateway │  │
│  └──────────────────┘   └────────┬───────────┘  │
└──────────────────────────────────┼──────────────┘
                                   │
                    HTTP GET (статус) / POST (команды)
                                   │
┌──────────────────────────────────┼──────────────┐
│  СЕТЬ КОНТУРА                     │              │
│                                  ▼              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  │
n│  │ Gateway 1  │  │ Gateway 2  │  │ Gateway N  │  │
│  │ 10.0.0.10  │  │ 10.0.0.11  │  │ 10.0.0.N   │  │
n│  └────────────┘  └────────────┘  └────────────┘  │
└─────────────────────────────────────────────────┘
```

---

## Установка

### Предварительные требования

- Docker + Docker Compose
- Сетевой доступ к Gateway-хостам (порт 18789 или настроенный порт)
- Отдельная машина (не та же что Gateway)

### Шаг 1: Скопировать

```bash
# Скопировать папку kill-switch на машину ИБ-отдела
scp -r kill-switch/ user@ib-machine:/opt/kill-switch/
```

### Шаг 2: Настроить список Gateway-хостов

Отредактировать `kill-switch/gateways.json`:

```json
{
  "gateways": [
    {
      "name": "Gateway-Отдел-Разработки",
      "host": "10.0.0.10",
      "port": 18789,
      "token": "gw-token-1"
    },
    {
      "name": "Gateway-Отдел-Бухгалтерии",
      "host": "10.0.0.11",
      "port": 18789,
      "token": "gw-token-2"
    }
  ],
  "pollIntervalMs": 10000,
  "logPath": "/var/log/kill-switch/operations.log"
}
```

### Шаг 3: Запустить

```bash
cd /opt/kill-switch
docker compose up -d
```

### Шаг 4: Открыть Dashboard

```
http://<IP_МАШИНЫ_ИБ>:8080
```

---

## Как пользоваться

### Обычная работа

1. Dashboard показывает таблицу всех Gateway-хостов и агентов
2. Зеленый = alive, красный = dead/offline
3. Статус обновляется автоматически каждые 10 секунд

### Остановка одного агента

1. Найти агента в таблице
2. Нажать «Остановить»
3. Подтвердить в диалоге
4. Watchdog отправляет команду → агент останавливается

### 🛑 EMERGENCY KILL ALL

1. Нажать красную кнопку «EMERGENCY KILL ALL»
2. Ввести подтверждение (текст из диалога)
3. Watchdog итерирует по ВСЕМ Gateway-хостам
4. Каждый Gateway получает команду shutdown
5. Если Gateway не отвечает → Docker stop / SSH kill
6. Все операции логируются

---

## Два уровня остановки

### Мягкая (через Gateway API)

- Watchdog → `POST http://<host>:18789/api/shutdown`
- Работает если Gateway жив
- Корректное завершение, сохранение state
- **Время:** ~2-5 секунд

### Жёсткая (через Docker API / SSH)

- Watchdog → `docker stop openclaw-gateway` (через Docker socket)
- Работает ВСЕГДА, даже если Gateway завис
- Данные текущих операций теряются
- **Время:** мгновенно

Жёсткая остановка используется как fallback, если мягкая не сработала в течение 10 секунд.

---

## Настройка Docker-доступа для жёсткой остановки

Если Kill Switch и Gateway на разных машинах, нужен доступ к Docker API:

### Вариант A: Docker socket через SSH

```bash
# На машине Kill Switch:
ssh -L /tmp/docker.sock:/var/run/docker.sock user@gateway-host
```

### Вариант B: Docker TCP (только внутри контура)

На Gateway-хосте в `/etc/docker/daemon.json`:
```json
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"]
}
```

На Kill Switch — добавить хост:port в `gateways.json`:
```json
{
  "name": "Gateway-1",
  "host": "10.0.0.10",
  "port": 18789,
  "dockerPort": 2375
}
```

### Вариант C: SSH-команды (самый простой)

Watchdog подключается по SSH и выполняет:
```bash
docker stop openclaw-airgap
# или
systemctl stop openclaw-gateway
```

Настроить SSH-ключи:
```bash
# На машине Kill Switch:
ssh-keygen -t ed25519 -f ~/.ssh/kill-switch
ssh-copy-id user@10.0.0.10
```

---

## Тестирование (Mac Mini → Windows)

### Подготовка

1. Mac Mini и Windows в одной WiFi/LAN сети
2. Узнать IP Windows: `ipconfig` в командной строке
3. Проверить доступность: `curl http://<IP_WINDOWS>:18789/healthz` с Mac Mini

### Запуск Kill Switch на Mac Mini

```bash
cd /opt/kill-switch  # или где скопировали
# В gateways.json указать IP Windows
docker compose up -d
# Открыть http://localhost:8080
```

### Проверить

1. Dashboard показывает Gateway на Windows как "alive"
2. Нажать "Остановить" → Gateway на Windows останавливается
3. Нажать "Перезапустить" → Gateway на Windows поднимается

---

## Логирование

Все операции Kill Switch логируются:

```
/var/log/kill-switch/operations.log
```

Формат:
```
[2026-05-18T12:00:00+03:00] KILL agent_id=main gateway=10.0.0.10 operator=ib-user@company.local reason="emergency"
[2026-05-18T12:00:05+03:00] KILL-ALL gateways=3 agents=12 operator=ib-user@company.local reason="security incident"
[2026-05-18T12:05:00+03:00] RESTART gateway=10.0.0.11 agent_id=main operator=ib-user@company.local
```

---

## Безопасность самого Kill Switch

- Dashboard за reverse proxy с auth (nginx + basic auth / SSO)
- IP-allowlist — только машины ИБ-отдела
- Все команды логируются с указанием оператора
- TLS обязателен (даже внутри контура)

---

## Структура файлов

```
kill-switch/
├── README.md                 ← этот файл
├── docker-compose.yml        ← watchdog + dashboard контейнеры
├── gateways.json.example     ← шаблон конфигурации Gateway-хостов
├── dashboard/
│   └── index.html            ← веб-UI (HTML/CSS/JS, без фреймворков)
└── watchdog/
    └── watchdog.py           ← логика опроса, kill, restart
```

---

## ✅ РЕАЛИЗОВАНО

- [x] docker-compose.yml (watchdog + nginx)
- [x] gateways.json.example
- [x] watchdog/watchdog.py — ядро логики (healthcheck, soft/hard kill, restart, logging, HTTP API)
- [x] watchdog/Dockerfile + requirements.txt
- [x] dashboard/index.html — UI
- [x] dashboard/style.css — стили (тёмная тема)
- [x] dashboard/app.js — логика UI (polling, модалки, kill-all)
- [x] nginx/default.conf — прокси к watchdog

## Оставшиеся задачи

- [ ] Тест: Mac Mini → Windows (одна LAN)
- [ ] Тест: Kill All (несколько Gateway)
- [ ] Auth для Dashboard (basic auth / SSO)
- [ ] HTTPS (TLS сертификат)

---

*Статус: Документация/ТЗ. Реализация — по готовности.*
*Создано: 2026-05-18*
