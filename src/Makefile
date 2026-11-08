# ------------------------------------------------------------------------------
# --- Defaults
# ------------------------------------------------------------------------------
.PHONY: default usage install start stop local-start local-stop api-docs
default: local-start
SHELL:=/bin/bash
# Name in the self-signed key of the backend (scripts/genkey.bash)
IMGNAME?=skeleton
# Python packages of the backend venv, pinned to the versions 2.0.0 was
# tested with (a newer websockets/SQLAlchemy may break the backend);
# installer/daas/install.bash reads this list too
VENV_INST="Quart==0.22.0 quart-cors==0.8.0 requests==2.34.2 aiohttp==3.14.5 websockets==17.4 flake8==7.5.0 pylint==4.1.3 pika==1.4.4 netifaces==0.11.0 psutil==7.2.2 SQLAlchemy==2.1.8 PyMySQL==1.2.3 pylint-per-file-ignores==4.0.0 black==26.10.1 types-requests==2.33.0.20261030 types-click==7.1.8 types-aiofiles==25.1.0.20261107 aiosqlite==0.22.1 docker==7.2.0"
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
	@echo "     api-docs: Write docs/api.md from the route definitions"
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
api-docs:
	.venv/bin/python3 scripts/api_docs.py
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
