#!/usr/bin/env bash
#
# ExecStart of daas.service: runs the backend (src/main.py) in the foreground
# with the venv's Python. exec: the backend is the service's main process,
# so systemd sends it the stop signal directly (no ExecStop needed).
# Output goes to the journal: journalctl -u daas -f (not to the installer
# log: this runs on every service start)

DAAS_LOG_FILE=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

DAAS_DIR="$(cd "$DAAS_INSTALLER_DIR/../src" && pwd)"
PYTHON="$DAAS_DIR/.venv/bin/python3"
[[ -x "$PYTHON" ]] || die "No venv in $DAAS_DIR (make daas-install)"

# Like `source .venv/bin/activate`: subprocesses find the venv's tools too
export VIRTUAL_ENV="$DAAS_DIR/.venv"
export PATH="$VIRTUAL_ENV/bin:$PATH"

info "Starting backend from $DAAS_DIR"
cd "$DAAS_DIR"
exec "$PYTHON" main.py
