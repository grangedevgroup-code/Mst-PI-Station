"""Unit tests for Aetherium config management."""

import pytest
import tempfile
import yaml
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from core.config import Config, _deep_merge


@pytest.fixture
def tmp_config(tmp_path):
    cfg_file = tmp_path / "aetherium.yaml"
    cfg_data = {
        "node": {"name": "test-node", "profile": "relay"},
        "hotspot": {"ssid": "TestNet", "channel": 6},
        "modules": {}
    }
    with open(cfg_file, "w") as f:
        yaml.dump(cfg_data, f)
    return Config(cfg_file)


def test_config_get_simple(tmp_config):
    assert tmp_config.get("node.name") == "test-node"


def test_config_get_nested(tmp_config):
    assert tmp_config.get("hotspot.ssid") == "TestNet"


def test_config_get_default(tmp_config):
    assert tmp_config.get("nonexistent.key", "fallback") == "fallback"


def test_config_set_simple(tmp_config):
    tmp_config.set("node.name", "new-name")
    assert tmp_config.get("node.name") == "new-name"


def test_config_set_nested(tmp_config):
    tmp_config.set("hotspot.channel", "11")
    assert tmp_config.get("hotspot.channel") == 11  # auto-coerced to int


def test_config_set_bool(tmp_config):
    tmp_config.set("hotspot.enabled", "true")
    assert tmp_config.get("hotspot.enabled") is True


def test_config_validate_ok(tmp_config):
    errors = tmp_config.validate()
    assert errors == []


def test_config_validate_invalid_profile(tmp_config):
    tmp_config.set("node.profile", "invalid-profile")
    errors = tmp_config.validate()
    assert any("profile" in e for e in errors)


def test_deep_merge():
    base = {"a": {"b": 1, "c": 2}, "d": 3}
    override = {"a": {"b": 99}, "e": 4}
    result = _deep_merge(base, override)
    assert result["a"]["b"] == 99
    assert result["a"]["c"] == 2
    assert result["d"] == 3
    assert result["e"] == 4


def test_config_save_and_reload(tmp_config):
    tmp_config.set("node.name", "saved-node")
    tmp_config.save()
    reloaded = Config(tmp_config.config_file)
    assert reloaded.get("node.name") == "saved-node"
