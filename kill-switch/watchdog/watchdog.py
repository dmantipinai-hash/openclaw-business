"""
Kill Switch Watchdog — ядро системы аварийной остановки агентов OpenClaw.
Опрашивает Gateway-хосты, отправляет команды остановки, ведёт лог.
"""

import json
import time
import logging
import argparse
import signal
import sys
import os
from datetime import datetime, timezone
from pathlib import Path

try:
    import requests
    from flask import Flask, jsonify, request as flask_request
except ImportError:
    print("Установка зависимостей: pip install requests flask")
    sys.exit(1)

# ═══ Конфигурация ═══

DEFAULT_CONFIG_PATH = "/etc/kill-switch/gateways.json"
DEFAULT_LOG_PATH = "/var/log/kill-switch/operations.log"

app = Flask(__name__)
logger = logging.getLogger("kill-switch")

# Глобальное состояние
config = None
gateway_states = {}  # host -> {status, agents, last_check, error}


# ═══ Логирование ═══

def setup_logging(log_path: str):
    """Настройка логирования в файл и консоль."""
    Path(log_path).parent.mkdir(parents=True, exist_ok=True)
    fh = logging.FileHandler(log_path, encoding="utf-8")
    fh.setFormatter(logging.Formatter(
        "[%(asctime)s] %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S%z"
    ))
    ch = logging.StreamHandler()
    ch.setFormatter(logging.Formatter("[%(asctime)s] %(levelname)s %(message)s"))
    logger.setLevel(logging.INFO)
    logger.addHandler(fh)
    logger.addHandler(ch)


def log_operation(action: str, gateway: str = "", agent_id: str = "",
                  operator: str = "", reason: str = "", details: str = ""):
    """Логировать операцию Kill Switch."""
    msg = f"{action}"
    if agent_id:
        msg += f" agent={agent_id}"
    if gateway:
        msg += f" gateway={gateway}"
    if operator:
        msg += f" operator={operator}"
    if reason:
        msg += f" reason={reason}"
    if details:
        msg += f" details={details}"
    logger.info(msg)


# ═══ Работа с Gateway ═══

def get_gateway_url(gw: dict, path: str = "") -> str:
    """Построить URL для запроса к Gateway."""
    base = f"http://{gw['host']}:{gw.get('port', 18789)}"
    return f"{base}{path}"


def check_gateway_health(gw: dict) -> dict:
    """Проверить здоровье Gateway. Возвращает статус."""
    try:
        url = get_gateway_url(gw, "/healthz")
        headers = {}
        if gw.get("token"):
            headers["Authorization"] = f"Bearer {gw['token']}"

        resp = requests.get(url, headers=headers, timeout=5)
        if resp.status_code == 200:
            return {"status": "alive", "error": None}
        else:
            return {"status": "error", "error": f"HTTP {resp.status_code}"}
    except requests.exceptions.ConnectionError:
        return {"status": "dead", "error": "connection refused"}
    except requests.exceptions.Timeout:
        return {"status": "timeout", "error": "timeout 5s"}
    except Exception as e:
        return {"status": "error", "error": str(e)}


def get_gateway_agents(gw: dict) -> list:
    """Получить список агентов с Gateway."""
    try:
        url = get_gateway_url(gw, "/api/agents")
        headers = {}
        if gw.get("token"):
            headers["Authorization"] = f"Bearer {gw['token']}"

        resp = requests.get(url, headers=headers, timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            return data if isinstance(data, list) else data.get("agents", [])
        return []
    except Exception:
        return []


def get_gateway_sessions(gw: dict) -> list:
    """Получить список активных сессий."""
    try:
        url = get_gateway_url(gw, "/api/sessions")
        headers = {}
        if gw.get("token"):
            headers["Authorization"] = f"Bearer {gw['token']}"

        resp = requests.get(url, headers=headers, timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            return data if isinstance(data, list) else data.get("sessions", [])
        return []
    except Exception:
        return []


def get_gateway_cron(gw: dict) -> list:
    """Получить список cron-задач."""
    try:
        url = get_gateway_url(gw, "/api/cron")
        headers = {}
        if gw.get("token"):
            headers["Authorization"] = f"Bearer {gw['token']}"

        resp = requests.get(url, headers=headers, timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            return data if isinstance(data, list) else data.get("jobs", [])
        return []
    except Exception:
        return []


# ═══ Команды остановки ═══

def soft_kill_gateway(gw: dict, operator: str = "", reason: str = "") -> dict:
    """Мягкая остановка через Gateway API."""
    try:
        url = get_gateway_url(gw, "/api/shutdown")
        headers = {"Content-Type": "application/json"}
        if gw.get("token"):
            headers["Authorization"] = f"Bearer {gw['token']}"

        resp = requests.post(url, headers=headers, timeout=10,
                             json={"reason": reason, "operator": operator})

        log_operation("SOFT-KILL-GATEWAY", gateway=gw["host"],
                      operator=operator, reason=reason,
                      details=f"status={resp.status_code}")

        if resp.status_code in (200, 202):
            return {"success": True, "method": "soft", "status_code": resp.status_code}
        else:
            return {"success": False, "method": "soft", "error": f"HTTP {resp.status_code}"}
    except Exception as e:
        log_operation("SOFT-KILL-FAILED", gateway=gw["host"],
                      operator=operator, reason=reason, details=str(e))
        return {"success": False, "method": "soft", "error": str(e)}


def hard_kill_gateway(gw: dict, operator: str = "", reason: str = "") -> dict:
    """Жёсткая остановка через Docker API или SSH."""
    docker_host = gw.get("dockerHost") or gw.get("host")
    docker_port = gw.get("dockerPort", 2375)

    # Попытка 1: Docker API
    try:
        url = f"http://{docker_host}:{docker_port}/containers/openclaw-airgap/stop"
        resp = requests.post(url, timeout=10)
        if resp.status_code in (200, 204, 304):
            log_operation("HARD-KILL-DOCKER", gateway=gw["host"],
                          operator=operator, reason=reason)
            return {"success": True, "method": "docker"}
    except Exception:
        pass

    # Попытка 2: SSH
    ssh_user = gw.get("sshUser")
    ssh_key = gw.get("sshKey")
    if ssh_user:
        try:
            import subprocess
            cmd = ["ssh"]
            if ssh_key:
                cmd.extend(["-i", ssh_key])
            cmd.extend([
                f"{ssh_user}@{gw['host']}",
                "docker stop openclaw-airgap 2>/dev/null || systemctl stop openclaw-gateway 2>/dev/null || pkill -f 'openclaw gateway'"
            ])
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            log_operation("HARD-KILL-SSH", gateway=gw["host"],
                          operator=operator, reason=reason,
                          details=f"exit={result.returncode}")
            return {"success": result.returncode == 0, "method": "ssh"}
        except Exception as e:
            log_operation("HARD-KILL-FAILED", gateway=gw["host"],
                          operator=operator, reason=reason, details=str(e))
            return {"success": False, "method": "ssh", "error": str(e)}

    return {"success": False, "method": "none", "error": "no docker or ssh access"}


def kill_gateway(gw: dict, operator: str = "", reason: str = "") -> dict:
    """Остановить Gateway: мягкая → жёсткая (fallback)."""
    # Сначала мягкая
    result = soft_kill_gateway(gw, operator, reason)
    if result["success"]:
        return result

    # Фолбэк: жёсткая через 5 секунд
    time.sleep(2)
    result = hard_kill_gateway(gw, operator, reason)
    return result


# ═══ Обновление состояния ═══

def poll_all_gateways():
    """Опросить все Gateway и обновить состояние."""
    if not config:
        return

    for gw in config.get("gateways", []):
        host = gw["host"]
        health = check_gateway_health(gw)

        state = {
            "name": gw.get("name", host),
            "host": host,
            "port": gw.get("port", 18789),
            "status": health["status"],
            "error": health["error"],
            "last_check": datetime.now(timezone.utc).isoformat(),
        }

        if health["status"] == "alive":
            state["agents"] = get_gateway_agents(gw)
            state["sessions"] = get_gateway_sessions(gw)
            state["cron_jobs"] = get_gateway_cron(gw)
        else:
            state["agents"] = []
            state["sessions"] = []
            state["cron_jobs"] = []

        gateway_states[host] = state


# ═══ HTTP API (для Dashboard) ═══

@app.route("/api/status")
def api_status():
    """Текущий статус всех Gateway."""
    return jsonify({
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "gateways": list(gateway_states.values()),
        "config_gateways": [
            {"name": gw.get("name", gw["host"]), "host": gw["host"], "port": gw.get("port", 18789)}
            for gw in config.get("gateways", [])
        ]
    })


@app.route("/api/gateways/<host>/kill", methods=["POST"])
def api_kill_gateway(host: str):
    """Остановить конкретный Gateway."""
    data = flask_request.json or {}
    operator = data.get("operator", "dashboard")
    reason = data.get("reason", "")

    gw = next((g for g in config.get("gateways", []) if g["host"] == host), None)
    if not gw:
        return jsonify({"error": f"Gateway {host} not found"}), 404

    result = kill_gateway(gw, operator, reason)
    status_code = 200 if result["success"] else 500
    return jsonify(result), status_code


@app.route("/api/kill-all", methods=["POST"])
def api_kill_all():
    """EMERGENCY: остановить ВСЕ Gateway."""
    data = flask_request.json or {}
    operator = data.get("operator", "dashboard")
    reason = data.get("reason", "emergency")

    log_operation("KILL-ALL", operator=operator, reason=reason,
                  details=f"gateways={len(config.get('gateways', []))}")

    results = []
    for gw in config.get("gateways", []):
        result = kill_gateway(gw, operator, reason)
        result["host"] = gw["host"]
        result["name"] = gw.get("name", gw["host"])
        results.append(result)

    # Обновить состояние
    poll_all_gateways()

    return jsonify({
        "action": "kill-all",
        "results": results,
        "timestamp": datetime.now(timezone.utc).isoformat()
    })


@app.route("/api/gateways/<host>/restart", methods=["POST"])
def api_restart_gateway(host: str):
    """Перезапустить Gateway (docker start)."""
    data = flask_request.json or {}
    operator = data.get("operator", "dashboard")

    gw = next((g for g in config.get("gateways", []) if g["host"] == host), None)
    if not gw:
        return jsonify({"error": f"Gateway {host} not found"}), 404

    docker_host = gw.get("dockerHost") or gw.get("host")
    docker_port = gw.get("dockerPort", 2375)

    try:
        url = f"http://{docker_host}:{docker_port}/containers/openclaw-airgap/start"
        resp = requests.post(url, timeout=15)
        log_operation("RESTART", gateway=host, operator=operator,
                      details=f"status={resp.status_code}")
        return jsonify({"success": resp.status_code in (200, 204), "status_code": resp.status_code})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/logs")
def api_logs():
    """Получить последние записи лога."""
    log_path = config.get("logPath", DEFAULT_LOG_PATH) if config else DEFAULT_LOG_PATH
    try:
        lines = Path(log_path).read_text(encoding="utf-8").strip().split("\n")
        last_lines = lines[-50:]  # последние 50 строк
        return jsonify({"logs": last_lines})
    except Exception:
        return jsonify({"logs": []})


# ═══ Фоновый опрос ═══

def background_poll():
    """Фоновая задача: периодический опрос Gateway."""
    poll_all_gateways()

    if config:
        interval = config.get("pollIntervalMs", 10000) / 1000
    else:
        interval = 10


# ═══ Точка входа ═══

def load_config(config_path: str) -> dict:
    """Загрузить конфигурацию."""
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        logger.error(f"Конфиг не найден: {config_path}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        logger.error(f"Ошибка парсинга конфига: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Kill Switch Watchdog")
    parser.add_argument("--config", default=DEFAULT_CONFIG_PATH,
                        help="Путь к конфигу (default: /etc/kill-switch/gateways.json)")
    parser.add_argument("--port", type=int, default=5000,
                        help="Порт HTTP API (default: 5000)")
    parser.add_argument("--log", default=DEFAULT_LOG_PATH,
                        help="Путь к логу (default: /var/log/kill-switch/operations.log)")
    args = parser.parse_args()

    global config
    config = load_config(args.config)
    setup_logging(args.log)

    logger.info("Kill Switch Watchdog запущен")
    logger.info(f"Конфиг: {args.config}")
    logger.info(f"Gateway-хостов: {len(config.get('gateways', []))}")
    logger.info(f"HTTP API порт: {args.port}")

    # Первичный опрос
    poll_all_gateways()

    # Запустить Flask
    app.run(host="0.0.0.0", port=args.port, threaded=True)


if __name__ == "__main__":
    main()
