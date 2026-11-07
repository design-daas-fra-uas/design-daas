#!/usr/bin/env bash
#
# Removes what daas/install.bash set up for the DaaS backend:
#   - daas.service (stopped, disabled, unit file deleted)
#   - the Python venv (src/.venv)
#
# Kept: src/config, src/data, the service/desktop images, nginx and
# docker-compose (shared with the frontend). With -p also:
#   - src/data (runtime data, recreated from src/data_template by
#     daas/configure.bash)
#   - the nginx site daas.conf
#
# Reinstall afterwards with `make daas-reinstall` or daas-install,
# daas-configure, daas-start.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

SERVICE_NAME="daas"
REPO_FOLDER="$(cd "$DAAS_INSTALLER_DIR/.." && pwd)"

usage() { echo "Usage: $0 [-p]   (-p: also delete src/data and the nginx site)" >&2; exit 1; }

PURGE=""
while getopts ":p" o; do
    case "$o" in
        p) PURGE=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

require_root

# ============================================================
step "systemd unit: $SERVICE_NAME.service"
# ============================================================

# Stopping sends SIGTERM to the backend, which stops its service containers
remove_unit "$SERVICE_NAME"

# ============================================================
step "Python environment"
# ============================================================

if [[ -d "$REPO_FOLDER/src/.venv" ]]; then
    run rm -rf "$REPO_FOLDER/src/.venv"
    success "Removed $REPO_FOLDER/src/.venv"
else
    info "No venv in $REPO_FOLDER/src"
fi

if [[ -n "$PURGE" ]]; then
    # ============================================================
    step "Purge: runtime data and nginx site"
    # ============================================================

    run rm -rf "$REPO_FOLDER/src/data"
    rm -f /etc/nginx/sites-enabled/daas.conf /etc/nginx/sites-available/daas.conf
    success "Removed src/data and the nginx site daas.conf"
    if systemctl is-active --quiet nginx; then
        run nginx -t
        run systemctl reload nginx
    fi
fi

success "DaaS backend deleted"
