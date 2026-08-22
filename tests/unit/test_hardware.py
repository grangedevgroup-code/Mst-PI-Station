"""Unit tests for hardware detection."""

import pytest
from unittest.mock import patch, MagicMock
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))


def test_hardware_basic_init():
    """Hardware should initialize without raising even without hardware.yaml."""
    from core.hardware import Hardware
    hw = Hardware()
    assert hw.arch is not None
    assert isinstance(hw.cpu_cores, int)
    assert hw.cpu_cores >= 1


def test_hardware_suggested_interfaces_fallback():
    from core.hardware import Hardware
    hw = Hardware()
    suggested = hw.suggested_interfaces()
    assert "ap" in suggested
    assert "mesh" in suggested
    assert "uplink" in suggested


def test_hardware_profile_warnings_no_wifi():
    from core.hardware import Hardware
    hw = Hardware()
    hw._data["interfaces"] = {"wifi": [], "ethernet": [], "wwan": []}
    warnings = hw.profile_warnings("relay")
    assert any("Wi-Fi" in w for w in warnings)


def test_hardware_has_rnode_false():
    from core.hardware import Hardware
    hw = Hardware()
    hw._data["devices"] = {"rnode": [], "lte_modem": []}
    assert hw.has_rnode is False
    assert hw.has_lte is False
