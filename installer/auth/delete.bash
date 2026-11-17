#!/usr/bin/env bash
#
# Removes what auth/install.bash set up:
#   - daas-auth.service (stopped, disabled, unit file deleted)
#   - the daas-auth container
#   - the daas-auth image (rebuilt from the current code on install)
#
# Kept: its database in the DaaS MariaDB and the token signing keys (docker
# volume), so users, permissions and issued tokens survive a reinstall.
# With -p (needs -e <env-file>) also:
#   - the database AUTH_DB_NAME and the user AUTH_DB_USER in daas-0-mariadb
#     (ALL users and permissions are lost; the admin is created again on the
#     next start), and the volume daas-auth_keys
#   - the generated compose env (installer/auth/.env)
#
# Reinstall afterwards with `make auth-reinstall`.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

SERVICE_NAME="daas-auth"
AUTH_DIR="$DAAS_INSTALLER_DIR/auth"
# Fixed by docker-compose.yml (name: daas-auth, container_name, image)
CONTAINERS=(daas-auth)
IMAGE="daas-auth"
VOLUMES=(daas-auth_keys)
# Left over from before the auth service used the DaaS MariaDB
OLD_CONTAINERS=(daas-auth-db)
OLD_VOLUMES=(daas-auth_db-data)
NETWORK="daas-auth_default"

usage() { echo "Usage: $0 [-p -e <env-file>]   (-p: also delete the database and keys)" >&2; exit 1; }

PURGE=""
ENV_FILE=""
while getopts ":pe:" o; do
    case "$o" in
        p) PURGE=1 ;;
        e) ENV_FILE="$OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

require_root
require_cmds docker
if [[ -n "$PURGE" ]]; then
    [[ -n "$ENV_FILE" ]] || usage
    load_stack_env "$ENV_FILE" >/dev/null
    [[ "$AUTH_DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || die "Unexpected characters in AUTH_DB_NAME"
    [[ "$AUTH_DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || die "Unexpected characters in AUTH_DB_USER"
fi

# ============================================================
step "systemd unit: $SERVICE_NAME.service"
# ============================================================

remove_unit "$SERVICE_NAME"

# ============================================================
step "Containers and image"
# ============================================================

for c in "${CONTAINERS[@]}" "${OLD_CONTAINERS[@]}"; do
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
    info "Keeping the database and the volumes ${VOLUMES[*]} (use -p to delete them)"
else
    warn "Deleting the auth service database and signing keys"
    if [[ -n "$(docker ps -q --filter "name=^$DAAS_DB_CONTAINER$")" ]]; then
        daas_db_sql <<SQL
DROP DATABASE IF EXISTS \`$AUTH_DB_NAME\`;
DROP USER IF EXISTS $(sql_string "$AUTH_DB_USER")@$(sql_string "$DAAS_DB_CLIENT_HOST");
SQL
        success "Dropped database $AUTH_DB_NAME and user $AUTH_DB_USER in $DAAS_DB_CONTAINER"
    else
        warn "$DAAS_DB_CONTAINER is not running: database $AUTH_DB_NAME kept (make db-start, then again)"
    fi
    for v in "${VOLUMES[@]}" "${OLD_VOLUMES[@]}"; do
        if docker volume inspect "$v" >/dev/null 2>&1; then
            run docker volume rm "$v"
        else
            info "No volume $v"
        fi
    done
    rm -f "$AUTH_DIR/.env"
fi

success "auth service deleted"
