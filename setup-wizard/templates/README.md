# Setup Wizard Templates

Шаблоны конфигураций для `setup.sh`.
Плейсхолдеры: `{{VARIABLE}}` — заменяются скриптом на реальные значения.

## Список шаблонов

| Файл | Описание |
|------|----------|
| `gateway.json5.template` | Конфиг OpenClaw Gateway (модели, auth, tools) |
| `tool-policy-strict.yaml.template` | Tool Policy: строгий профиль |
| `tool-policy-standard.yaml.template` | Tool Policy: стандартный профиль |
| `tool-policy-sandboxed.yaml.template` | Tool Policy: sandboxed профиль |
| `docker-compose.yml.template` | Docker Compose (gateway + ollama + kill-switch) |
| `env.template` | Переменные окружения (.env) |
