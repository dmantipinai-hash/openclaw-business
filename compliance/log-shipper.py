#!/usr/bin/env python3
"""
OpenClaw Compliance Log Shipper — прототип.

Читает логи OpenClaw, формирует записи в стандартном формате,
отправляет batch-запросом на Compliance Server.

Запускается как systemd (Linux) или launchd (macOS) сервис.
Пользователь НЕ может его отключить.

Использование:
  python3 log-shipper.py --config shipper-config.json
"""

import json
import time
import glob
import hashlib
import logging
import argparse
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import requests
except ImportError:
    print("pip install requests")
    sys.exit(1)

# ═══ Конфигурация ═══

DEFAULT_CONFIG = {
    "openclaw_logs_dir": os.path.expanduser("~/.openclaw/logs"),
    "compliance_url": "https://compliance.corp.local/api/v1/audit/batch",
    "compliance_token": "<TOKEN>",
    "source_name": "openclaw-gateway-1",
    "poll_interval_seconds": 30,
    "batch_size": 100,
    "state_file": "/var/lib/openclaw-shipper/state.json",
    "buffer_dir": "/var/lib/openclaw-shipper/buffer"
}

logger = logging.getLogger("openclaw-shipper")


# ═══ State (позиция чтения) ═══

def load_state(state_file: str) -> dict:
    """Загрузить состояние — до какой позиции дочитаны логи."""
    try:
        with open(state_file, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state_file: str, state: dict):
    """Сохранить состояние."""
    Path(state_file).parent.mkdir(parents=True, exist_ok=True)
    with open(state_file, "w") as f:
        json.dump(state, f, indent=2)


# ═══ Чтение логов ═══

def read_new_entries(log_dir: str, state: dict) -> list:
    """
    Прочитать новые записи из логов OpenClaw.
    Возвращает список audit-записей.
    """
    entries = []
    log_files = glob.glob(os.path.join(log_dir, "**/*.jsonl"), recursive=True)
    log_files += glob.glob(os.path.join(log_dir, "**/*.json"), recursive=True)

    for log_file in log_files:
        file_state = state.get(log_file, {"offset": 0})
        offset = file_state["offset"]

        try:
            with open(log_file, "r", encoding="utf-8") as f:
                f.seek(offset)
                new_lines = f.readlines()
                new_offset = f.tell()

            if new_lines:
                state[log_file] = {"offset": new_offset}

                for line in new_lines:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        raw = json.loads(line)
                        entry = normalize_entry(raw, log_file)
                        if entry:
                            entries.append(entry)
                    except json.JSONDecodeError:
                        # Строка без JSON — логируем как raw
                        entries.append({
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                            "type": "raw_log",
                            "source_file": log_file,
                            "content_hash": hashlib.sha256(line.encode()).hexdigest()[:16],
                            "content_length": len(line)
                        })
        except Exception as e:
            logger.warning(f"Cannot read {log_file}: {e}")

    return entries


def normalize_entry(raw: dict, source_file: str) -> dict:
    """
    Привести запись лога к стандартному формату.
    
    Стандартный формат:
    {
      "timestamp": "ISO8601",
      "user_id": "...",
      "session_id": "...",
      "agent_id": "...",
      "type": "tool_call | user_message | file_write | exec_command | ...",
      "tool": "...",
      "input_summary": "...",
      "output_summary": "...",
      "duration_ms": N,
      "risk_level": "low | medium | high"
    }
    """
    # Извлечь поля из разных форматов логов OpenClaw
    entry = {
        "timestamp": raw.get("timestamp") or raw.get("time") or datetime.now(timezone.utc).isoformat(),
        "user_id": raw.get("userId") or raw.get("user_id") or raw.get("sender") or "unknown",
        "session_id": raw.get("sessionId") or raw.get("session_id") or raw.get("sessionKey") or "",
        "agent_id": raw.get("agentId") or raw.get("agent_id") or "main",
        "type": classify_event(raw),
        "source_file": os.path.basename(source_file),
    }

    # Дополнить полями если есть
    if "tool" in raw or "toolName" in raw:
        entry["tool"] = raw.get("tool") or raw.get("toolName")
        entry["input_summary"] = summarize(raw.get("input") or raw.get("args") or "", max_len=200)
        entry["output_summary"] = summarize(raw.get("output") or raw.get("result") or "", max_len=200)

    if "command" in raw or "cmd" in raw:
        entry["exec_command"] = raw.get("command") or raw.get("cmd")

    entry["risk_level"] = assess_risk(entry)

    return entry


def classify_event(raw: dict) -> str:
    """Определить тип события."""
    if raw.get("tool") or raw.get("toolName"):
        return "tool_call"
    if raw.get("role") == "user" or raw.get("type") == "user_message":
        return "user_message"
    if raw.get("role") == "assistant" or raw.get("type") == "assistant_message":
        return "agent_response"
    if raw.get("command") or raw.get("cmd"):
        return "exec_command"
    if "file" in str(raw.get("path", "")):
        return "file_operation"
    if raw.get("type") == "config_change":
        return "config_change"
    return "unknown"


def summarize(text, max_len=200) -> str:
    """Сократить текст до max_len символов."""
    if not isinstance(text, str):
        text = str(text)
    if len(text) <= max_len:
        return text
    return text[:max_len] + "..."


RISKY_TOOLS = {"exec", "browser", "web_search", "web_fetch", "sessions_spawn"}
RISKY_KEYWORDS = {"rm ", "delete", "drop", "truncate", "sudo", "chmod"}


def assess_risk(entry: dict) -> str:
    """Оценить уровень риска действия."""
    tool = entry.get("tool", "")
    cmd = entry.get("exec_command", "")

    if tool in RISKY_TOOLS:
        return "high"
    if any(kw in cmd.lower() for kw in RISKY_KEYWORDS):
        return "high"
    if tool in ("read", "memory_search", "memory_get"):
        return "low"
    return "medium"


# ═══ Отправка ═══

def send_batch(url: str, token: str, source: str, entries: list) -> bool:
    """Отправить batch записей на Compliance Server."""
    if not entries:
        return True

    payload = {
        "source": source,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "count": len(entries),
        "entries": entries
    }

    try:
        resp = requests.post(
            url,
            json=payload,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json"
            },
            timeout=30
        )
        if resp.status_code in (200, 201, 202):
            logger.info(f"Sent {len(entries)} entries to compliance server")
            return True
        else:
            logger.warning(f"Compliance server returned {resp.status_code}: {resp.text[:200]}")
            return False
    except Exception as e:
        logger.error(f"Failed to send to compliance server: {e}")
        return False


def buffer_entries(buffer_dir: str, entries: list):
    """Буферизировать записи при невозможности отправки."""
    Path(buffer_dir).mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    path = os.path.join(buffer_dir, f"buffer-{ts}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False, indent=2)
    logger.info(f"Buffered {len(entries)} entries to {path}")


# ═══ Главный цикл ═══

def run_shipper(config: dict):
    """Основной цикл log shipper."""
    state_file = config.get("state_file", "/var/lib/openclaw-shipper/state.json")
    state = load_state(state_file)

    while True:
        # Прочитать новые записи
        entries = read_new_entries(config["openclaw_logs_dir"], state)

        if entries:
            # Отправить
            success = send_batch(
                config["compliance_url"],
                config["compliance_token"],
                config["source_name"],
                entries
            )

            if success:
                # Сохранить позицию
                save_state(state_file, state)
            else:
                # Буферизировать
                buffer_entries(config.get("buffer_dir", "/var/lib/openclaw-shipper/buffer"), entries)

        interval = config.get("poll_interval_seconds", 30)
        time.sleep(interval)


def main():
    parser = argparse.ArgumentParser(description="OpenClaw Compliance Log Shipper")
    parser.add_argument("--config", default="shipper-config.json", help="Путь к конфигу")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(levelname)s %(message)s")

    try:
        with open(args.config, "r", encoding="utf-8") as f:
            config = {**DEFAULT_CONFIG, **json.load(f)}
    except FileNotFoundError:
        logger.warning(f"Config not found: {args.config}, using defaults")
        config = DEFAULT_CONFIG

    logger.info(f"Log Shipper started. Source: {config['source_name']}")
    logger.info(f"Reading from: {config['openclaw_logs_dir']}")
    logger.info(f"Sending to: {config['compliance_url']}")

    run_shipper(config)


if __name__ == "__main__":
    main()
