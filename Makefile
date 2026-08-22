# Aetherium Makefile
# Development, testing, and deployment helpers

INSTALL_DIR ?= /opt/aetherium
VENV        := $(INSTALL_DIR)/venv
PYTHON      := $(VENV)/bin/python3
PIP         := $(VENV)/bin/pip

.PHONY: all install dev-install lint test clean help

all: help

help:
	@echo "Aetherium build targets:"
	@echo ""
	@echo "  make install         Install Aetherium to $(INSTALL_DIR)"
	@echo "  make dev-install     Install in dev mode with editable packages"
	@echo "  make venv            Create Python virtual environment"
	@echo "  make lint            Run linting (flake8, shellcheck)"
	@echo "  make test            Run unit tests"
	@echo "  make test-hardware   Run on-device hardware tests"
	@echo "  make status          Show node status"
	@echo "  make clean           Remove build artifacts"
	@echo "  make dev-vm          Set up QEMU ARM dev VM"
	@echo ""

install:
	@echo "Installing Aetherium..."
	sudo bash install.sh

dev-install:
	@echo "Installing in development mode..."
	pip install -e . --quiet 2>/dev/null || true
	pip install -r dashboard/requirements.txt --quiet
	pip install flake8 shellcheck-py pytest pytest-asyncio --quiet

venv:
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install jinja2 pyyaml click rich fastapi uvicorn[standard] psutil aiofiles python-multipart

lint:
	@echo "Linting Python..."
	$(PYTHON) -m flake8 bin/ core/ dashboard/ --max-line-length=120 --ignore=E501,W503 || true
	@echo "Linting shell scripts..."
	find . -name "*.sh" -not -path "*/SourceDependencies/*" | xargs shellcheck --severity=warning || true

test:
	@echo "Running unit tests..."
	$(PYTHON) -m pytest tests/unit/ -v

test-hardware:
	@echo "Running hardware tests (must run on target device)..."
	$(PYTHON) -m pytest tests/hardware/ -v

status:
	aetherium status

clean:
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.egg-info" -type d -exec rm -rf {} + 2>/dev/null || true

dev-vm:
	bash hack/dev-vm-setup.sh
