"""Shared fixtures for Kill Switch tests."""
import json
import pytest
import sys
import os

# Add watchdog dir to path so we can import watchdog.py
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import watchdog as wd


@pytest.fixture
def sample_gateways_config():
    """Sample gateways.json config."""
    return {
        "gateways": [
            {
                "name": "GW-Test-1",
                "host": "10.0.0.10",
                "port": 18789,
                "token": "test-token-123",
                "dockerHost": "10.0.0.10",
                "dockerPort": 2375,
            },
            {
                "name": "GW-Test-2",
                "host": "10.0.0.20",
                "port": 18789,
                "token": None,
            },
        ],
        "pollIntervalMs": 10000,
        "logPath": "/tmp/kill-switch-test/operations.log",
    }


@pytest.fixture
def app_client(sample_gateways_config):
    """Flask test client with config loaded."""
    wd.config = sample_gateways_config
    wd.gateway_states = {}
    wd.app.config["TESTING"] = True
    with wd.app.test_client() as client:
        yield client
