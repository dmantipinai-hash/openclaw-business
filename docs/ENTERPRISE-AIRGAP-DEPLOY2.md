# OpenClaw Enterprise Air-Gap Deployment (Draft v2)

> Практическое ТЗ / архитектурная записка для внедрения OpenClaw в закрытом корпоративном контуре.
>
> Цель документа — не «идеальная презентация», а реалистичный список того, что можно и нужно сделать в OpenClaw для безопасного enterprise-развёртывания без выхода в публичный интернет.

---

## 1. Цель

Развернуть OpenClaw в закрытом или строго ограниченном контуре так, чтобы:

- агент **не зависел от публичных SaaS-провайдеров**;
- весь трафик шёл только по **внутренним адресам / доверенному прокси**;
- аутентификация сотрудников была завязана на **корпоративный identity layer**;
- логи, память, документы и интеграции **не покидали контур**;
- модель безопасности опиралась не на «доверие к агенту», а на:
  - сетевые ограничения,
  - auth boundary,
  - tool policy,
  - sandboxing,
  - аудит.

---

## 2. Сценарии, для которых это нужно

Подход рассчитан на такие сценарии:

1. **Внутренний корпоративный чат-ассистент**
   - отвечает на вопросы по внутренней документации;
   - помогает искать регламенты, инструкции, владельцев сервисов;
   - работает в Web UI или внутреннем мессенджере.

2. **Ассистент для инженерных команд**
   - работает с внутренним GitLab/Gitea;
   - помогает с кодом, CI, runbook'ами, внутренними API;
   - не имеет доступа к публичному GitHub по умолчанию.

3. **Ассистент над внутренними системами**
   - только через согласованные интеграции;
   - только по внутренним API;
   - с read-only / draft-first режимом на старте.

---

## 3. Негласное правило: business = не «больше функций», а «жёстче границы»

Если смотреть глазами бизнеса, то ключевая ценность не в количестве skills, а в том, что система:

- предсказуемо ограничена;
- наблюдаема;
- проверяема аудитом;
- не зависит от ноутбука одного разработчика;
- не ломает политику ИБ.

Поэтому enterprise-версия OpenClaw должна строиться вокруг **ограничений по умолчанию**, а не вокруг полной свободы агента.

---

## 4. Базовые требования безопасности

### 4.1. Сетевой периметр

OpenClaw не должен иметь произвольного выхода в интернет.

Требования:

- Gateway доступен только:
  - на `loopback`, либо
  - через внутренний reverse proxy / tailnet / LAN с auth;
- публичный internet ingress запрещён;
- egress ограничен firewall / proxy allowlist;
- разрешены только:
  - внутренний LLM endpoint;
  - внутренние API интеграций;
  - внутренние registry / mirror / package sources;
  - внутренние observability endpoints.

### 4.2. Аутентификация

Для non-loopback сценариев использовать:

- `gateway.auth.mode: "trusted-proxy"` через identity-aware reverse proxy,
  **или**
- token/password auth для строго сервисных контуров.

Предпочтительно для enterprise:

- SSO на уровне прокси (Keycloak / Authentik / корпоративный IdP);
- OpenClaw доверяет только заголовкам от **trusted proxy**;
- прямой доступ к Gateway в обход прокси запрещён firewall'ом.

### 4.3. Авторизация

Даже после входа пользователя инструменты должны быть ограничены по профилю.

Минимум:

- deny-by-default для опасных tool surfaces;
- разные профили для read-only, operator, engineering, automation;
- запрет делегации (`sessions_spawn`) там, где она не нужна;
- sandboxing для агентных запусков, где возможен код/exec.

### 4.4. Аудит

Должны сохраняться:

- кто обратился к системе;
- какой агент/маршрут обработал запрос;
- какие инструменты вызывались;
- какие внешние/внутренние endpoints затрагивались;
- какие изменения были произведены.

Логи и аудит — только внутри контура.

---

## 5. Целевая архитектура

```text
[User Browser / Internal Chat]
          |
          v
[Identity-aware Reverse Proxy]
          |
          v
[OpenClaw Gateway]
   |        |         |
   |        |         +--> [Internal observability: logs / OTEL / SIEM]
   |        |
   |        +------------> [Internal tools / APIs / GitLab / Docs / LDAP]
   |
   +---------------------> [Internal LLM provider: Ollama / vLLM / compatible API]
```

### Основная идея

- OpenClaw — orchestration layer;
- модель — локальная или self-hosted внутри контура;
- auth — на trusted reverse proxy;
- доступ к данным — только через внутренние интеграции и allowlist.

---

## 6. Модели: только self-hosted или внутренний inference endpoint

OpenClaw по умолчанию часто используют с внешними провайдерами, но для air-gap / enterprise это нежелательно.

### Допустимые варианты

1. **Ollama**
   - простой старт;
   - подходит для пилота, R&D, локальных команд;
   - хуже масштабируется под большой concurrent load.

2. **vLLM**
   - предпочтительно для production и shared inference;
   - лучше для нескольких команд / высокой нагрузки;
   - удобнее как единый внутренний OpenAI-compatible endpoint.

3. **Другой внутренний OpenAI-compatible слой**
   - если в компании уже есть стандартный inference gateway.

### Требования

- model endpoint доступен по **внутреннему URL**;
- сертификаты внутренних CA должны быть доверены Node.js (`NODE_EXTRA_CA_CERTS` при необходимости);
- модель не должна требовать доступа во внешний интернет во время runtime.

### Практический вывод

Для бизнеса лучше формулировать не «локальная модель», а:

**«внутренний inference provider с контролируемым SLA, логированием и сетевым периметром»**.

---

## 7. Каналы доступа

В air-gap окружении использовать только внутренние каналы.

### Рекомендуемые

- Web UI / Control UI за корпоративным reverse proxy;
- Mattermost / Matrix / Slack Enterprise Grid — только если реально внутренние;
- внутренние HTTP/API-интерфейсы.

### Не рекомендуется по умолчанию

- Telegram;
- WhatsApp;
- Signal;
- любые публичные облачные мессенджеры без отдельного security exception.

### Политика

- DM и group access — через allowlist policy;
- внешние публичные боты — вне базового enterprise scope.

---

## 8. Политика инструментов (tool policy)

Это центральная часть enterprise-доработки.

### Что должно быть запрещено или ограничено по умолчанию

- `web_search` — отключить либо заменить внутренним поиском;
- `web_fetch` — только для внутренних доменов / через allowlist;
- любые tools, работающие с публичными API — выключить;
- `browser` — только если есть понятный security case;
- `computer_use` — только на выделенных, контролируемых рабочих станциях;
- `sessions_spawn` — отключить, если делегация не нужна;
- `exec` / кодовые инструменты — только в sandbox-профиле.

### Что нужно сохранить

- безопасные read-only workflow;
- внутренние API-интеграции;
- поиск по внутренним знаниям;
- аудит вызовов инструментов.

### Правило зрелости

Запускать систему лучше в трёх режимах:

1. **Read-only / Draft**
2. **Write with approval**
3. **Automation / Scheduled**

У бизнеса почти всегда правильный старт — **Read-only / Draft**.

---

## 9. Sandbox и ограничение исполнения

Если агенту нужен код, shell, обработка файлов или генерация артефактов, это должно идти через ограниченное выполнение.

### Требования

- sandbox для агентных запусков, где есть риск записи / exec;
- `workspaceOnly` там, где применимо;
- отдельные рабочие директории под команды / задачи;
- запрет свободного доступа ко всей ФС хоста.

### Практический смысл

Enterprise-заказчик почти всегда хочет не «агент на всей машине», а:

- агент в выделенном workspace;
- agent-run в изолированной среде;
- воспроизводимый журнал действий.

---

## 10. Память, знания, RAG

### 10.1. Что важно бизнесу

Бизнесу обычно важнее не «память личности агента», а:

- ответы по корпоративным документам;
- поиск по регламентам;
- поиск по runbook'ам;
- история решений и инцидентов.

### 10.2. Минимальный вариант

- файловая память и `memory_search`;
- индекс только по разрешённым документам;
- без внешнего embedding provider.

### 10.3. Более зрелый вариант

- внутренний embedding backend;
- векторный store внутри контура;
- отдельные наборы знаний по подразделениям;
- контроль видимости на уровне коллекций / путей.

### Практическая формулировка для ТЗ

Не писать абстрактно «RAG для всего предприятия».
Лучше так:

- Phase 1: FAQ + политики + runbook'и;
- Phase 2: инженерная документация и внутренние API;
- Phase 3: разграничение доступа к knowledge collections.

---

## 11. Интеграции с внутренними системами

Приоритет — не «подключить всё подряд», а сделать несколько управляемых интеграций.

### Подход

Каждая интеграция должна иметь:

- отдельный owner;
- отдельный credential scope;
- отдельный allowlist endpoints;
- отдельную роль/профиль агента;
- audit trail.

### Первыми обычно нужны

1. **GitLab / Gitea**
   - чтение репозиториев;
   - issues / merge requests;
   - CI status.

2. **Внутренний docs portal / wiki**
   - корпоративные знания;
   - инструкции;
   - FAQ.

3. **LDAP / AD / directory**
   - read-only lookup;
   - оргструктура;
   - владельцы сервисов.

4. **Внутренние HTTP API**
   - только через согласованный контракт;
   - без прямой «магии» поверх prod-систем на старте.

### Важно

Первый production rollout должен начинаться с **read-only интеграций**.

---

## 12. Supply chain и оффлайн-сборка

Для air-gap сред критично не только runtime, но и lifecycle поставки.

### Требования

- все npm/pnpm зависимости должны быть доступны из внутреннего source / mirror;
- Docker images — через внутренний registry (например, Harbor);
- обновления OpenClaw — через контролируемый import в контур;
- scan уязвимостей — внутри контура;
- сборка должна быть воспроизводимой без обращения к публичным registry.

### Практика

- использовать внутренний npm mirror / cache;
- собирать Docker image заранее и переносить в контур как артефакт;
- использовать внутренний image registry;
- фиксировать версии зависимостей и базовых образов.

---

## 13. TLS и корпоративные сертификаты

В enterprise-контуре часто используются собственные CA.

### Нужно предусмотреть

- доверие к внутреннему TLS на стороне Node.js;
- `NODE_EXTRA_CA_CERTS` для Gateway/daemon при необходимости;
- единый документ: какие CA должны быть установлены на host / container.

### Почему это важно

Без этого OpenClaw может «выглядеть сломанным», хотя проблема банально в том, что Node не доверяет внутренним сертификатам.

---

## 14. Логирование, наблюдаемость, аудит

OpenClaw уже имеет file logging и security audit. Для enterprise этого достаточно как базы, но не как финальной observability-стратегии.

### Обязательный минимум

- включённые file logs;
- ротация логов;
- redaction sensitive data;
- регулярный запуск `openclaw security audit` и `openclaw security audit --deep`;
- централизованный сбор логов во внутренний stack.

### Желательно

- OTEL/внутренний observability pipeline;
- корреляция user -> session -> agent -> tool call;
- отдельный отчёт по risky config findings.

### Что важно зафиксировать в ТЗ

Не просто «собирать логи», а:

- где они хранятся;
- сколько живут;
- кто имеет доступ;
- как маскируются секреты;
- как выгружаются на расследование инцидентов.

---

## 15. Жёсткая позиция по network exposure

Для enterprise-релиза нужно прямо зафиксировать следующее:

- OpenClaw **не должен** быть публично торчащим в интернет;
- non-loopback bind допустим только с auth + firewall / private ingress;
- trusted-proxy — это осознанный security boundary и должен проходить отдельный review;
- внешний reverse proxy без корректной identity chain — недостаточен.

Это важно, потому что в enterprise главное — не «открыть доступ поудобнее», а минимизировать плоскость атаки.

---

## 16. Что в исходном draft было полезным, но стоит переформулировать

Ниже — моменты, которые по смыслу полезны, но в ТЗ лучше формулировать иначе.

### Было слишком абстрактно

- «делегаты»
- «агент бухгалтерии»
- «агент разработчиков»
- «кастомные плагины для всего»

### Лучше писать так

- profile-based agent routing;
- role-scoped tool access;
- read-only first rollout;
- controlled internal integrations;
- sandboxed automation only after pilot.

### Было спорно / неочевидно как публичная функция

- упоминания внутренних файлов/символов как будто это готовые enterprise features;
- ссылки на условные `role-policy.ts`, `control-plane-audit.ts`, `workspace-delegate` как на готовый продуктовый интерфейс.

### Лучше

Описывать не внутренние имена файлов, а требования уровня системы:

- RBAC / profile separation;
- auditability;
- allowlisted tools;
- restricted transport;
- internal identity integration.

---

## 17. Матрица реализации (3 колонки)

Ниже — та самая раскладка, которую имеет смысл держать как рабочую карту.

**Важно:** галочка в этой секции означает не «уже реализовано в продукте под enterprise из коробки», а:

- пункт подтверждён по текущему репозиторию OpenClaw;
- он **не противоречит архитектуре**;
- его можно брать как реалистичный baseline без большой переделки;
- я специально отметил самые простые ограничения, которые уже можно внедрять как первую волну hardening.

| Уже есть в OpenClaw | Можно внедрить без большой переделки | Требует отдельной доработки / отдельного бизнес-ТЗ |
|---|---|---|
| `gateway.auth.mode: "trusted-proxy"`, `trustedProxies`, отдельная документация по trusted proxy auth | [x] **Ограничить ingress**: loopback по умолчанию или private reverse proxy вместо публичного internet ingress | [ ] Полноценная enterprise SSO-обвязка с корпоративными ролями и жизненным циклом пользователей |
| Поддержка self-hosted/local models: `ollama`, `vllm`, OpenAI-compatible endpoints | [x] **Перевести модель на внутренний inference provider** вместо публичных SaaS | [ ] Единый внутренний inference gateway с SLA, quota, chargeback и multi-tenant governance |
| `openclaw security audit`, `--deep`, `--fix`, security docs и check catalog | [x] **Сделать security audit baseline** обязательной частью пилота и эксплуатации | [ ] Автоматизированная compliance-обвязка, отдельные security dashboards и policy-as-code поверх аудита |
| Tool policy: `tools.profile`, `tools.allow`, `tools.deny`, per-sender/per-provider restrictions | [x] **Сделать deny-by-default tool baseline**: отключить лишние web/UI/automation surfaces для enterprise-пилота | [ ] Тонкая RBAC/ABAC-модель по отделам, бизнес-ролям и операциям |
| Sandbox: `agents.defaults.sandbox.*`, `workspaceAccess`, `docker.network`, `non-main/all` | [x] **Включить sandbox для рискованных сессий** и ограничить workspace access | [ ] Жёстко профилированные песочницы под разные бизнес-домены и утверждённые execution classes |
| Workspace/file guardrails: `tools.exec.applyPatch.workspaceOnly`, `tools.fs.workspaceOnly` | [x] **Ограничить файловую поверхность** workspace-only guardrails там, где это допустимо | [ ] Политика классификации данных, связанная с DLP и разграничением наборов документов |
| Поддержка внутренних каналов и политик доступа: Matrix, Mattermost, allowlist/groupPolicy/dmPolicy | [x] **Оставить только внутренние каналы** и fail-closed allowlist policy для DM/group access | [ ] Полноценная омниканальная enterprise-маршрутизация с едиными профилями доступа и согласованием с ИБ |
| Logging/redaction/OTEL surfaces уже предусмотрены в архитектуре | [x] **Включить file logs + redaction + внутренний log shipping** как минимальный baseline | [ ] Полноценный SOC/SIEM pipeline с расследованиями, ретеншном, legal hold и e-discovery |
| `NODE_EXTRA_CA_CERTS` и startup TLS trust path есть в коде/тестах | [x] **Зафиксировать доверие к внутренним CA** как обязательное требование контура | [ ] Централизованная PKI/onboarding-автоматизация хостов и контейнеров |
| `channels.matrix`, `channels.mattermost`, allowlist, mention gating, internal proxy options | [x] **Стартовать с read-only/internal messaging model** вместо публичных каналов и внешних ботов | [ ] Глубокая бизнес-интеграция каналов с approval workflows и корпоративными политиками хранения |
| `memorySearch`, extra paths, remote/local providers, knowledge-oriented config surfaces | [x] **Ограничить knowledge scope** только разрешёнными документами и внутренними источниками | [ ] Полноценный enterprise RAG с коллекциями по подразделениям, ACL и data residency policy |
| Общая архитектура OpenClaw допускает безопасный read-only first rollout | [x] **Запускать пилот в режиме Read-only / Draft first** | [ ] Write-actions with approvals, DLP на исходящие сообщения и безопасные бизнес-операции поверх API |

### Что именно я пометил как «самое простое» и уже зафиксировал в baseline

Ниже — 8 пунктов из прошлого ответа, которые выглядят реалистично **без большой переделки** и уже отражены в этом документе как рекомендуемый baseline:

- [x] закрытый deployment с внутренним LLM;
- [x] trusted-proxy + SSO на прокси;
- [x] ограничение network exposure;
- [x] security audit как baseline;
- [x] отключение/ограничение опасных tools;
- [x] работа только с внутренними каналами;
- [x] доверие к внутренним CA через `NODE_EXTRA_CA_CERTS`;
- [x] read-only стартовый режим.

### Что я сделал в рамках этой задачи

- [x] перепроверил эти пункты по репозиторию `openclaw-business` и локальным докам проекта;
- [x] отделил реальные текущие возможности от enterprise-пожеланий;
- [x] разложил `ENTERPRISE-AIRGAP-DEPLOY2.md` на 3 практические корзины: already exists / config+infra / needs dev;
- [x] отметил галочками только то, что выглядит как безопасный и реалистичный baseline без большой переделки.

---

## 18. Минимальный MVP для бизнеса

Если делать не «идеальный enterprise forever», а реальный первый этап, я бы предложил такой scope.

### Phase 1 — Secure Pilot

- OpenClaw Gateway внутри контура;
- внутренний LLM endpoint (Ollama/vLLM);
- только Web UI за reverse proxy;
- SSO / trusted-proxy auth;
- deny-by-default tool policy;
- read-only knowledge access;
- file logs + security audit;
- firewall egress allowlist.

### Phase 2 — Internal Knowledge Assistant

- memory / RAG по внутренним документам;
- wiki / docs / runbook ingestion;
- LDAP / AD read-only lookup;
- централизованный лог-сбор.

### Phase 3 — Controlled Integrations

- GitLab/Gitea;
- внутренние API;
- draft-first write actions;
- workflow approvals.

### Phase 4 — Automation

- cron / background tasks только для разрешённых use cases;
- sandboxed delegated runs;
- отдельные service profiles;
- расширенный аудит.

---

## 19. Чек-лист готовности к production

Систему нельзя считать готовой к enterprise rollout, пока не подтверждено следующее:

### Архитектура
- [ ] Gateway не exposed в public internet
- [ ] весь ingress идёт через контролируемый internal path
- [ ] есть внутренний inference provider
- [ ] все внешние SaaS-зависимости удалены или явно разрешены

### Безопасность
- [ ] настроен gateway auth
- [ ] если используется trusted-proxy — определены trusted proxies и header contract
- [ ] egress ограничен firewall / proxy allowlist
- [ ] dangerous tools ограничены policy / sandbox
- [ ] настроен redaction sensitive data

### Эксплуатация
- [ ] есть централизованные логи
- [ ] есть процедура обновления в оффлайн-контуре
- [ ] есть внутренний registry / mirror для артефактов
- [ ] есть процедура отката
- [ ] есть security audit baseline

### Данные
- [ ] определено, какие документы можно индексировать
- [ ] определено, какие данные нельзя возвращать пользователю
- [ ] определены правила хранения логов, памяти и артефактов

---

## 20. Рекомендуемая формулировка бизнес-ТЗ

Если сжать всё в короткое ТЗ, я бы предложил такую редакцию:

> Требуется адаптировать OpenClaw для развёртывания во внутреннем корпоративном контуре без зависимости от публичного интернета. Решение должно поддерживать внутренний LLM provider, корпоративную аутентификацию через trusted reverse proxy / SSO, строгую tool policy, sandboxing для рискованных операций, централизованное логирование и аудит. Система должна работать по модели deny-by-default, поддерживать read-only стартовый режим, интеграцию с внутренними knowledge sources и ограниченный набор внутренних API. Отдельно требуется предусмотреть оффлайн-поставку зависимостей, доверие к внутренним CA, процедуру security audit и безопасный update pipeline.

---

## 21. Что я бы предложил делать дальше

Следующий полезный шаг — не сразу кодить, а разбить работу на 3 артефакта:

1. **Architecture doc**
   - целевая схема развёртывания;
   - trust boundaries;
   - ingress/egress;
   - auth flow.

2. **Security baseline**
   - обязательные настройки OpenClaw;
   - запреты по tools;
   - sandbox / workspace restrictions;
   - логирование и аудит.

3. **Implementation backlog**
   - что уже есть в OpenClaw из коробки;
   - что настраивается конфигом;
   - что нужно дописать как business-specific extension.

---

## 22. Вывод

Исходный файл был полезен как brainstorming, но для бизнеса важнее не список модных слов, а чёткая связка:

- **какая угроза**,
- **какая граница доверия**,
- **какой контролирующий механизм**,
- **как это проверяется**.

Если делать enterprise-ветку всерьёз, то главный вектор такой:

**OpenClaw as internal orchestration layer with strict auth, strict network boundaries, strict tool policy, and auditable internal integrations.**

---

*Файл создан как уточнённая и более реалистичная версия исходного draft.*
*Имя сохранено по вашей просьбе с суффиксом `2`.*
