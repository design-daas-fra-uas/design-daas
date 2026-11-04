#!/usr/bin/env bash
#
# Removes what java/install.bash set up:
#   - java-backend.service (stopped, disabled, unit file deleted)
#   - the daas-java-backend and daas-java-db containers
#   - the daas-java-backend image (rebuilt from the current code on install)
#
# Kept: the database and the token signing keys (docker volumes), so users,
# permissions and issued tokens survive a reinstall. With -p also:
#   - the volumes daas-java_db-data and daas-java_keys (ALL users and
#     permissions are lost; the admin is created again on the next start)
#   - the generated compose env (installer/java/.env)
#
# Reinstall afterwards with `make java-reinstall`.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

SERVICE_NAME="java-backend"
JAVA_DIR="$DAAS_INSTALLER_DIR/java"
# Fixed by docker-compose.yml (name: daas-java, container_name, image)
CONTAINERS=(daas-java-backend daas-java-db)
IMAGE="daas-java-backend"
VOLUMES=(daas-java_db-data daas-java_keys)
NETWORK="daas-java_default"

usage() { echo "Usage: $0 [-p]   (-p: also delete the database and keys)" >&2; exit 1; }

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

# ============================================================
step "systemd unit: $SERVICE_NAME.service"
# ============================================================

remove_unit "$SERVICE_NAME"

# ============================================================
step "Containers and image"
# ============================================================

for c in "${CONTAINERS[@]}"; do
    if [[ -n "$(docker ps -aq --filter "name=^${c}$")" ]]; then
        run docker rm -f "$c"
    else
        info "No container $c"
    fi
done
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    run docker network rm "$NETWORK"
fi
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    run docker image rm "$IMAGE"
else
    info "No image $IMAGE"
fi

# ============================================================
step "Data"
# ============================================================

if [[ -z "$PURGE" ]]; then
    info "Keeping the volumes ${VOLUMES[*]} (use -p to delete them)"
else
    warn "Deleting the Java database and signing keys"
    for v in "${VOLUMES[@]}"; do
        if docker volume inspect "$v" >/dev/null 2>&1; then
            run docker volume rm "$v"
        else
            info "No volume $v"
        fi
    done
    rm -f "$JAVA_DIR/.env"
fi

success "Java backend deleted"
