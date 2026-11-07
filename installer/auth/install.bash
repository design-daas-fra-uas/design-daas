#!/usr/bin/env bash
#
# Installs the auth service (users, OAuth tokens, permissions) with its own
# MariaDB as daas-auth.service (docker-compose, 127.0.0.1:AUTH_PORT).
# All settings come from the stack env file (installer/daas.env).
#
# The image is rebuilt from the current Java code on every run; the
# database and the token signing keys are kept. To start from scratch use
# `make auth-reinstall` (auth/delete.bash, -p also drops the data).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

SERVICE_NAME="daas-auth"
AUTH_DIR="$DAAS_INSTALLER_DIR/auth"
COMPOSE_FILE="$AUTH_DIR/docker-compose.yml"
COMPOSE_ENV="$AUTH_DIR/.env"

usage() {
    cat <<EOF >&2
Usage: $0 -e <env-file>

Options:
    -e    Stack env file (installer/daas.env)
EOF
    exit 1
}

ENV_FILE=""
while getopts ":e:" o; do
    case "$o" in
        e) ENV_FILE="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$ENV_FILE" ]] || usage
require_root
require_cmds docker docker-compose systemctl curl
load_stack_env "$ENV_FILE"
require_dir "$AUTH_FOLDER"
require_file "$AUTH_FOLDER/Dockerfile"

for secret in ADMIN_EMAIL ADMIN_PASSWORD AUTH_DB_PASSWORD AUTH_DB_ROOT_PASSWORD; do
    warn_default_secret "$secret"
done

info "auth service: $AUTH_FOLDER"
info "Listening:    127.0.0.1:$AUTH_PORT (public: $AUTH_PUBLIC_URL)"
info "Profile:      $AUTH_PROFILE"

# ============================================================
step "Compose env ($COMPOSE_ENV)"
# ============================================================

write_compose_env "$COMPOSE_ENV" \
    AUTH_FOLDER AUTH_PORT AUTH_PROFILE \
    AUTH_DB_NAME AUTH_DB_USER AUTH_DB_PASSWORD AUTH_DB_ROOT_PASSWORD \
    ADMIN_EMAIL ADMIN_PASSWORD \
    AUTH_PUBLIC_URL FRONTEND_PUBLIC_URL \
    OAUTH_ACCESS_TOKEN_TTL_SECONDS OAUTH_REFRESH_TOKEN_TTL_DAYS \
    MAIL_ENABLED MAIL_HOST MAIL_PORT MAIL_USERNAME MAIL_PASSWORD MAIL_FROM

COMPOSE=(docker-compose --env-file "$COMPOSE_ENV" -f "$COMPOSE_FILE")
run "${COMPOSE[@]}" config --quiet

# ============================================================
step "Build image"
# ============================================================

run "${COMPOSE[@]}" build

# ============================================================
step "systemd unit: $SERVICE_NAME.service"
# ============================================================

write_file "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Design DaaS auth service (users, OAuth, permissions)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$AUTH_DIR
ExecStart=/usr/bin/docker-compose --env-file $COMPOSE_ENV -f $COMPOSE_FILE up
ExecStop=/usr/bin/docker-compose --env-file $COMPOSE_ENV -f $COMPOSE_FILE down
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

run systemctl daemon-reload
enable_and_restart "$SERVICE_NAME.service"

# ============================================================
step "Wait for the auth service"
# ============================================================

# First start runs the DB migrations, so give it a while
URL="http://127.0.0.1:$AUTH_PORT/oauth2/user/token"
if ! wait_http "$URL"; then
    "${COMPOSE[@]}" logs --tail 50 backend || true
    die "auth service did not answer after 5 min (logs: make auth-logs)"
fi

# The DaaS backend logs in with the admin account; check it works
step "Check admin login"
resp="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "username=$ADMIN_EMAIL" \
    --data-urlencode "password=$ADMIN_PASSWORD" \
    --data-urlencode "scope=admin" || true)"
if [[ "$resp" == 200 ]]; then
    success "Admin login works ($ADMIN_EMAIL)"
else
    warn "Admin login returned HTTP $resp. The admin is only created on the first start;"
    warn "if you changed ADMIN_PASSWORD later, change it in the auth service too."
fi

success "auth service installed (logs: make auth-logs)"
