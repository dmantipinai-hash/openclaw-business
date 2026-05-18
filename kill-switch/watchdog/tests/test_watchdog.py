"""
Unit tests for Kill Switch Watchdog.
All external HTTP calls are mocked — no real Gateway needed.
"""

import json
import pytest
from unittest.mock import patch, MagicMock
import requests

import watchdog as wd


# ═══════════════════════════════════════════════════════════════
# 1. Health check — watchdog Flask app starts and responds
# ═══════════════════════════════════════════════════════════════

class TestHealthCheck:
    """Watchdog starts and serves /api/status."""

    def test_status_endpoint_returns_200(self, app_client):
        resp = app_client.get("/api/status")
        assert resp.status_code == 200

    def test_status_has_timestamp(self, app_client):
        resp = app_client.get("/api/status")
        data = resp.get_json()
        assert "timestamp" in data

    def test_status_lists_configured_gateways(self, app_client):
        resp = app_client.get("/api/status")
        data = resp.get_json()
        assert len(data["config_gateways"]) == 2
        hosts = [g["host"] for g in data["config_gateways"]]
        assert "10.0.0.10" in hosts
        assert "10.0.0.20" in hosts


# ═══════════════════════════════════════════════════════════════
# 2. Soft kill (graceful shutdown via Gateway API)
# ═══════════════════════════════════════════════════════════════

class TestSoftKill:
    """Graceful shutdown via POST /api/shutdown on Gateway."""

    @patch("watchdog.requests.post")
    def test_soft_kill_success(self, mock_post, app_client):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_post.return_value = mock_resp

        resp = app_client.post(
            "/api/gateways/10.0.0.10/kill",
            json={"operator": "tester", "reason": "maintenance"},
        )
        data = resp.get_json()
        assert data["success"] is True
        assert data["method"] == "soft"

    @patch("watchdog.requests.post")
    def test_soft_kill_sends_correct_url(self, mock_post, app_client):
        mock_resp = MagicMock()
        mock_resp.status_code = 202
        mock_post.return_value = mock_resp

        app_client.post(
            "/api/gateways/10.0.0.10/kill",
            json={"operator": "admin", "reason": "test"},
        )

        # First call is the soft kill attempt
        call_args = mock_post.call_args_list[0]
        assert "/api/shutdown" in call_args[0][0]

    @patch("watchdog.requests.post")
    def test_soft_kill_sends_auth_token(self, mock_post, app_client):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_post.return_value = mock_resp

        app_client.post(
            "/api/gateways/10.0.0.10/kill",
            json={"operator": "admin"},
        )

        call_args = mock_post.call_args_list[0]
        headers = call_args[1].get("headers", call_args[0][0] if len(call_args[0]) > 1 else {})
        # Check that Authorization header was passed
        assert any("Bearer" in str(v) for v in (headers.values() if isinstance(headers, dict) else []))


# ═══════════════════════════════════════════════════════════════
# 3. Hard kill (kill process / Docker stop)
# ═══════════════════════════════════════════════════════════════

class TestHardKill:
    """Hard kill via Docker API fallback."""

    @patch("watchdog.requests.post")
    def test_hard_kill_via_docker(self, mock_post, app_client):
        # Soft kill fails (500), then Docker stop succeeds (204)
        mock_post.side_effect = [
            MagicMock(status_code=500),  # soft kill fails
            MagicMock(status_code=204),  # docker stop succeeds
        ]

        resp = app_client.post(
            "/api/gateways/10.0.0.10/kill",
            json={"operator": "admin", "reason": "unresponsive"},
        )
        data = resp.get_json()
        assert data["success"] is True
        assert data["method"] == "docker"

    @patch("watchdog.requests.post")
    def test_hard_kill_all_methods_fail(self, mock_post, app_client):
        # Both soft and Docker fail
        mock_post.side_effect = [
            MagicMock(status_code=500),      # soft kill
            Exception("Connection refused"), # docker
        ]

        resp = app_client.post(
            "/api/gateways/10.0.0.10/kill",
            json={"operator": "admin"},
        )
        data = resp.get_json()
        assert data["success"] is False


# ═══════════════════════════════════════════════════════════════
# 4. EMERGENCY KILL ALL
# ═══════════════════════════════════════════════════════════════

class TestKillAll:
    """Emergency stop for ALL gateways."""

    @patch("watchdog.poll_all_gateways")
    @patch("watchdog.requests.post")
    def test_kill_all_stops_every_gateway(self, mock_post, mock_poll, app_client):
        # Soft kill succeeds for both gateways
        mock_post.return_value = MagicMock(status_code=200)
        mock_poll.return_value = None

        resp = app_client.post(
            "/api/kill-all",
            json={"operator": "security", "reason": "emergency"},
        )
        data = resp.get_json()
        assert data["action"] == "kill-all"
        assert len(data["results"]) == 2
        assert all(r["success"] for r in data["results"])

    @patch("watchdog.poll_all_gateways")
    @patch("watchdog.requests.post")
    def test_kill_all_returns_timestamp(self, mock_post, mock_poll, app_client):
        mock_post.return_value = MagicMock(status_code=200)
        mock_poll.return_value = None

        resp = app_client.post("/api/kill-all", json={})
        data = resp.get_json()
        assert "timestamp" in data

    @patch("watchdog.poll_all_gateways")
    @patch("watchdog.requests.post")
    def test_kill_all_partial_failure(self, mock_post, mock_poll, app_client):
        # First gateway succeeds, second fails
        mock_post.side_effect = [
            MagicMock(status_code=200),       # GW-1 soft kill OK
            MagicMock(status_code=500),       # GW-2 soft kill fail
            Exception("Connection refused"),  # GW-2 docker fail
        ]
        mock_poll.return_value = None

        resp = app_client.post("/api/kill-all", json={})
        data = resp.get_json()
        assert len(data["results"]) == 2
        assert data["results"][0]["success"] is True
        assert data["results"][1]["success"] is False


# ═══════════════════════════════════════════════════════════════
# 5. Restart gateway
# ═══════════════════════════════════════════════════════════════

class TestRestart:
    """Restart a gateway via Docker API."""

    @patch("watchdog.requests.post")
    def test_restart_success(self, mock_post, app_client):
        mock_post.return_value = MagicMock(status_code=204)

        resp = app_client.post(
            "/api/gateways/10.0.0.10/restart",
            json={"operator": "admin"},
        )
        data = resp.get_json()
        assert data["success"] is True

    @patch("watchdog.requests.post")
    def test_restart_calls_docker_start(self, mock_post, app_client):
        mock_post.return_value = MagicMock(status_code=200)

        app_client.post("/api/gateways/10.0.0.10/restart", json={})

        call_url = mock_post.call_args[0][0]
        assert "/containers/openclaw-airgap/start" in call_url

    @patch("watchdog.requests.post")
    def test_restart_failure(self, mock_post, app_client):
        mock_post.side_effect = Exception("Docker not available")

        resp = app_client.post(
            "/api/gateways/10.0.0.10/restart",
            json={},
        )
        assert resp.status_code == 500
        data = resp.get_json()
        assert data["success"] is False

    def test_restart_unknown_gateway_404(self, app_client):
        resp = app_client.post(
            "/api/gateways/99.99.99.99/restart",
            json={},
        )
        assert resp.status_code == 404


# ═══════════════════════════════════════════════════════════════
# 6. Get agents from Gateway
# ═══════════════════════════════════════════════════════════════

class TestGetAgents:
    """Fetching agent list from a Gateway."""

    @patch("watchdog.requests.get")
    def test_get_agents_returns_list(self, mock_get):
        mock_get.return_value = MagicMock(
            status_code=200,
            json=lambda: [{"id": "agent-1", "name": "Astra"}, {"id": "agent-2", "name": "Stik"}],
        )

        gw = {"host": "10.0.0.10", "port": 18789, "token": "test"}
        agents = wd.get_gateway_agents(gw)

        assert len(agents) == 2
        assert agents[0]["name"] == "Astra"

    @patch("watchdog.requests.get")
    def test_get_agents_with_nested_format(self, mock_get):
        mock_get.return_value = MagicMock(
            status_code=200,
            json=lambda: {"agents": [{"id": "a1"}]},
        )

        gw = {"host": "10.0.0.10", "port": 18789}
        agents = wd.get_gateway_agents(gw)
        assert len(agents) == 1

    @patch("watchdog.requests.get")
    def test_get_agents_network_error(self, mock_get):
        mock_get.side_effect = requests.exceptions.ConnectionError("refused")

        gw = {"host": "10.0.0.10", "port": 18789}
        agents = wd.get_gateway_agents(gw)
        assert agents == []

    @patch("watchdog.requests.get")
    def test_get_agents_non_200(self, mock_get):
        mock_get.return_value = MagicMock(status_code=403, json=lambda: {})

        gw = {"host": "10.0.0.10", "port": 18789}
        agents = wd.get_gateway_agents(gw)
        assert agents == []


# ═══════════════════════════════════════════════════════════════
# 7. Gateway health check
# ═══════════════════════════════════════════════════════════════

class TestGatewayHealth:
    """Checking individual gateway health."""

    @patch("watchdog.requests.get")
    def test_gateway_alive(self, mock_get):
        mock_get.return_value = MagicMock(status_code=200)
        gw = {"host": "10.0.0.10", "port": 18789}
        result = wd.check_gateway_health(gw)
        assert result["status"] == "alive"
        assert result["error"] is None

    @patch("watchdog.requests.get")
    def test_gateway_dead(self, mock_get):
        mock_get.side_effect = requests.exceptions.ConnectionError("refused")
        gw = {"host": "10.0.0.10", "port": 18789}
        result = wd.check_gateway_health(gw)
        assert result["status"] == "dead"

    @patch("watchdog.requests.get")
    def test_gateway_timeout(self, mock_get):
        mock_get.side_effect = requests.exceptions.Timeout("5s")
        gw = {"host": "10.0.0.10", "port": 18789}
        result = wd.check_gateway_health(gw)
        assert result["status"] == "timeout"


# ═══════════════════════════════════════════════════════════════
# 8. Config and URL helpers
# ═══════════════════════════════════════════════════════════════

class TestHelpers:
    """Utility functions."""

    def test_get_gateway_url_with_path(self):
        gw = {"host": "192.168.1.5", "port": 18789}
        url = wd.get_gateway_url(gw, "/api/agents")
        assert url == "http://192.168.1.5:18789/api/agents"

    def test_get_gateway_url_default_port(self):
        gw = {"host": "10.0.0.1"}
        url = wd.get_gateway_url(gw, "/healthz")
        assert url == "http://10.0.0.1:18789/healthz"

    def test_kill_unknown_gateway_returns_404(self, app_client):
        resp = app_client.post(
            "/api/gateways/unknown.host/kill",
            json={"operator": "admin"},
        )
        assert resp.status_code == 404


# ═══════════════════════════════════════════════════════════════
# 9. Logs endpoint
# ═══════════════════════════════════════════════════════════════

class TestLogs:
    """Logs API."""

    def test_logs_returns_json(self, app_client):
        resp = app_client.get("/api/logs")
        assert resp.status_code == 200
        data = resp.get_json()
        assert "logs" in data

    def test_logs_missing_file_returns_empty(self, app_client):
        resp = app_client.get("/api/logs")
        data = resp.get_json()
        assert data["logs"] == []
