# Security Test Suite

Автоматическая проверка безопасности конфигурации OpenClaw Enterprise.

## Быстрый старт

```bash
# Сгенерировать конфиги
cd setup-wizard && ./setup.sh

# Запустить тесты
cd ../security-tests && ./run-tests.sh ../output/

# Посмотреть отчёт
cat ../output/security-report.md
```

## Что проверяется

| Категория | Проверок | Примеры |
|-----------|----------|---------|
| 🔒 Tool Policy | 7 | deny-all, web_search заблокирован, exec ограничен |
| ⚙️ Gateway | 5 | bind не публичный, auth настроен, нет внешних LLM |
| 🔐 Секреты | 3 | нет API-ключей, токен задан |
| 🔴 Kill Switch | 2 | настроен, отвечает |
| 🐳 Docker | 3 | сеть internal, hardened |
| 📋 Compliance | 1 | endpoint доступен |

**Итого: 21 проверка**

## Форматы отчётов

```bash
# Markdown (по умолчанию)
./run-tests.sh ./output/ markdown

# JSON (для программного использования)
./run-tests.sh ./output/ json
```

## Добавление новых проверок

1. Добавить чек в `checks.yaml`:
```yaml
- id: my-new-check
  category: my_category
  severity: critical
  description: "Описание проверки"
  test: "my_test_function"
```

2. Добавить функцию в `lib/checks/`:
```bash
my_test_function() {
  local config_dir="$1" id="$2" sev="$3" desc="$4"
  # Логика проверки...
  record_pass "$desc" "$sev" "$id"
  # или
  record_fail "$desc" "$sev" "$id"
}
```

3. Добавить case в `run-tests.sh`
