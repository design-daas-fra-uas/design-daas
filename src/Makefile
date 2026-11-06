# ------------------------------------------------------------------------------
# --- Defaults
# ------------------------------------------------------------------------------
.PHONY: default usage install start stop local-start local-stop
default: local-start
SHELL:=/bin/bash
# Name in the self-signed key of the backend (scripts/genkey.bash)
IMGNAME?=skeleton
# Python packages of the backend venv; installer/daas/install.bash reads this
# list too
VENV_INST="quart quart-cors requests aiohttp websockets flake8 pylint pika netifaces psutil sqlalchemy pymysql pylint-per-file-ignores black types-requests types-click types-aiofiles nest_asyncio aiosqlite docker"
# ------------------------------------------------------------------------------
# --- Help
# ------------------------------------------------------------------------------
usage:
	@echo "make TARGET"
	@echo "   TARGETS: "
	@echo "     usage  : Help message"
	@echo "     install: Create the venv and the TLS key"
	@echo "     start  : Start the backend in the foreground"
	@echo "     stop   : Stop the backend"
	@echo ""
	@echo "   Normally the backend runs as daas.service (see installer/)."
# ------------------------------------------------------------------------------
# --- Host targets
# ------------------------------------------------------------------------------
install:
	@echo "--- LOCAL INSTALL ----------------"
	rm -rf .venv
	mkdir -p data/keys
	./scripts/ensure_venv.bash -p $(VENV_INST)
	./scripts/genkey.bash -f -n $(IMGNAME)
local-start: stop
	@echo "--- LOCAL START ------------------"
	@source ./.venv/bin/activate && python3 main.py
local-stop:
	@echo "--- LOCAL STOP -------------------"
	-pkill -f "python3 main.py"
# ------------------------------------------------------------------------------
# --- Common targets
# ------------------------------------------------------------------------------
start: | stop default

stop: local-stop
