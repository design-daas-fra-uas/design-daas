#!/usr/bin/env bash
#
# Removes what frontend/install.bash set up:
#   - frontend.service (stopped, disabled, unit file deleted)
#   - the daas-frontend container and image
#   - the generated compose env (installer/frontend/.env)
#
# Kept: the frontend repository and the nginx site. With -p also:
#   - the nginx site frontend.conf (recreated by frontend/configure.bash)
#
# Reinstall afterwards with `make frontend-reinstall`.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

SERVICE_NAME="frontend"
FRONTEND_DIR="$DAAS_INSTALLER_DIR/frontend"
CONTAINER="daas-frontend"
IMAGE="daas-frontend"

usage() { echo "Usage: $0 [-p]   (-p: also delete the nginx site)" >&2; exit 1; }

PURGE=""
while getopts ":p" o; do
    case "$o" in
        p) PURGE=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

require_root
require_cmds docker

# Installs before the compose file moved into the installer ran it from
# the frontend repo (docker-compose-pve.yml); clean that up as well.
LEGACY_FOLDER=""
if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
    LEGACY_FOLDER="$(systemctl show -p WorkingDirectory --value "$SERVICE_NAME.service" || true)"
    [[ "$LEGACY_FOLDER" != "$FRONTEND_DIR" ]] || LEGACY_FOLDER=""
fi

# ============================================================
step "systemd unit: $SERVICE_NAME.service"
# ============================================================

remove_unit "$SERVICE_NAME"

# ============================================================
step "Container and image"
# ============================================================

if [[ -n "$(docker ps -aq --filter "name=^${CONTAINER}$")" ]]; then
    run docker rm -f "$CONTAINER"
else
    info "No container $CONTAINER"
fi
if [[ -n "$LEGACY_FOLDER" && -f "$LEGACY_FOLDER/docker-compose-pve.yml" ]]; then
    info "Removing the old install from $LEGACY_FOLDER"
    run docker-compose -f "$LEGACY_FOLDER/docker-compose-pve.yml" \
        --project-directory "$LEGACY_FOLDER" down --rmi local --remove-orphans
    run rm -f "$LEGACY_FOLDER/docker-compose-pve.yml"
fi
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    run docker image rm "$IMAGE"
else
    info "No image $IMAGE"
fi
rm -f "$FRONTEND_DIR/.env"

if [[ -n "$PURGE" ]]; then
    # ============================================================
    step "Purge: nginx site"
    # ============================================================

    rm -f /etc/nginx/sites-enabled/frontend.conf /etc/nginx/sites-available/frontend.conf
    success "Removed the nginx site frontend.conf"
    if systemctl is-active --quiet nginx; then
        run nginx -t
        run systemctl reload nginx
    fi
fi

success "Frontend deleted"
