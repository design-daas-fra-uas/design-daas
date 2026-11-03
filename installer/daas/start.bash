#!/usr/bin/env bash
#
# ExecStart of daas.service: runs the backend in the foreground (src/Makefile
# local-start). Output goes to the journal: journalctl -u daas -f

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

DAAS_DIR="$(cd "$DAAS_INSTALLER_DIR/../src" && pwd)"
require_dir "$DAAS_DIR/.venv"

info "Starting backend from $DAAS_DIR"
cd "$DAAS_DIR"
# exec so systemd tracks make (and the backend) directly
exec make local-start
