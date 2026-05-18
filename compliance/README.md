# OpenClaw Compliance Log Shipper

> Прототип для отправки логов агента в отдельный сервис отдела комплаенс.

## Что это

Минимальный сервис, который:
1. Читает логи OpenClaw (`~/.openclaw/logs/`)
2. Формирует записи в стандартном формате (JSON)
3. Отправляет на Compliance Server (batch)
4. Буферизирует при недоступности сервера

## Установка

### Linux (systemd)

```bash
sudo cp log-shipper.py /opt/openclaw-shipper/
sudo cp shipper-config.json /etc/openclaw-shipper/
sudo cp log-shipper.service /etc/systemd/system/
sudo systemctl enable --now log-shipper
```

### macOS (launchd)

```bash
sudo cp log-shipper.py /opt/openclaw-shipper/
sudo cp shipper-config.json /etc/openclaw-shipper/
sudo cp com.openclaw.log-shipper.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.openclaw.log-shipper.plist
```

## Конфигурация (`shipper-config.json`)

```json
{
  "openclaw_logs_dir": "/home/user/.openclaw/logs",
  "compliance_url": "https://compliance.corp.local/api/v1/audit/batch",
  "compliance_token": "<TOKEN>",
  "source_name": "openclaw-gateway-1",
  "poll_interval_seconds": 30,
  "batch_size": 100
}
```

## Compliance Server API

Сервер на стороне предприятия должен реализовать:

### POST /api/v1/audit/batch

```json
{
  "source": "openclaw-gateway-1",
  "timestamp": "2026-05-18T13:45:00Z",
  "count": 5,
  "entries": [...]
}
```

Ответы: `200 OK` | `401 Unauthorized` | `429 Rate Limited`

### GET /api/v1/audit?user=X&from=YYYY-MM-DD&to=YYYY-MM-DD

Запрос истории по пользователю и датам.

## Варианты реализации сервера

- ELK Stack (Elasticsearch + Logstash + Kibana)
- SIEM (Splunk, QRadar, Wazuh)
- Свой API (PostgreSQL + Flask/FastAPI)
- Любой вариант, соответствующий политике ИБ

## Принцип

Пользователь **не может** удалить или изменить логи — они отправляются на отдельную машину.
Аналогично Kill Switch: критический компонент живёт отдельно от агента.
