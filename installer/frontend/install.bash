#!/usr/bin/env bash
#
# Builds the frontend image and installs frontend.service
# (docker-compose, published on 127.0.0.1:5001).
#
# With -e <env-file> the backend URLs are baked into the build
# (REACT_APP_* build args, see installer/daas.env.example). Without it the
# frontend falls back to its built-in defaults.
#
# The image is rebuilt from the current frontend code on every run; to
# start from scratch use `make frontend-reinstall` (frontend/delete.bash).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

SERVICE_NAME="frontend"
FRONTEND_DIR="$DAAS_INSTALLER_DIR/frontend"
COMPOSE_FILE="$FRONTEND_DIR/docker-compose.yml"
COMPOSE_ENV="$FRONTEND_DIR/.env"

usage() {
    cat <<EOF >&2
Usage: $0 -f <frontend-folder> [-r <repo-folder>] [-e <env-file>]

Options:
    -f    Frontend repository folder
    -r    Design DaaS repository folder (unused, accepted for symmetry)
    -e    Stack env file (installer/daas.env) with the public URLs
EOF
    exit 1
}

FRONTEND_FOLDER=""
ENV_FILE=""
while getopts ":r:f:e:" o; do
    case "$o" in
        r) ;;
        f) FRONTEND_FOLDER="$OPTARG" ;;
        e) ENV_FILE="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$FRONTEND_FOLDER" ]] || usage
require_root
require_cmds docker docker-compose systemctl
require_dir "$FRONTEND_FOLDER"
FRONTEND_FOLDER="$(realpath "$FRONTEND_FOLDER")"

if [[ -n "$ENV_FILE" ]]; then
    CLI_FRONTEND_FOLDER="$FRONTEND_FOLDER"
    load_stack_env "$ENV_FILE"
    FRONTEND_FOLDER="$CLI_FRONTEND_FOLDER"
    if ! grep -q "REACT_APP_DAAS_API_URL" "$FRONTEND_FOLDER/Dockerfile"; then
        warn "The frontend Dockerfile does not declare ARG REACT_APP_DAAS_API_URL;"
        warn "the URLs below will be ignored by the build (see frontend-env-urls.patch)"
    fi
    info "DaaS API:   $DAAS_PUBLIC_URL"
    info "Auth API:   $AUTH_PUBLIC_URL"
    info "Client id:  $OAUTH_CLIENT_ID"
else
    info "No env file given (-e), building with the frontend's default URLs"
    DAAS_PUBLIC_URL="" AUTH_PUBLIC_URL="" OAUTH_CLIENT_ID=""
fi
export FRONTEND_FOLDER

info "Frontend: $FRONTEND_FOLDER"

# ============================================================
step "Compose env ($COMPOSE_ENV)"
# ============================================================

write_compose_env "$COMPOSE_ENV" FRONTEND_FOLDER DAAS_PUBLIC_URL AUTH_PUBLIC_URL OAUTH_CLIENT_ID

COMPOSE=(docker-compose --env-file "$COMPOSE_ENV" -f "$COMPOSE_FILE")
run "${COMPOSE[@]}" config --quiet

# ============================================================
step "Build frontend image"
# ============================================================

run "${COMPOSE[@]}" build

# ============================================================
step "systemd unit: $SERVICE_NAME.service"
# ============================================================

write_file "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Design DaaS Frontend
After=docker.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$FRONTEND_DIR
ExecStart=/usr/bin/docker-compose --env-file $COMPOSE_ENV -f $COMPOSE_FILE up
ExecStop=/usr/bin/docker-compose --env-file $COMPOSE_ENV -f $COMPOSE_FILE down
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

run systemctl daemon-reload
# A daas-frontend container from the old compose file in the frontend repo
# would block the name
old_project="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' daas-frontend 2>/dev/null || true)"
if [[ -n "$old_project" && "$old_project" != daas-frontend ]]; then
    warn "Removing daas-frontend from the old compose project '$old_project'"
    run docker rm -f daas-frontend
fi
# restart: a running container is recreated from the new image
enable_and_restart "$SERVICE_NAME.service"

success "Frontend installed (logs: make frontend-logs)"
