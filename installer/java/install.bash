#!/usr/bin/env bash
#
# Installs the Java backend (users, OAuth tokens, permissions) with its own
# MariaDB as java-backend.service (docker-compose, 127.0.0.1:JAVA_PORT).
# All settings come from the stack env file (installer/daas.env).
#
# The image is rebuilt from the current Java code on every run; the
# database and the token signing keys are kept. To start from scratch use
# `make java-reinstall` (java/delete.bash, -p also drops the data).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

SERVICE_NAME="java-backend"
JAVA_DIR="$DAAS_INSTALLER_DIR/java"
COMPOSE_FILE="$JAVA_DIR/docker-compose.yml"
COMPOSE_ENV="$JAVA_DIR/.env"

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
require_dir "$JAVA_BACKEND_FOLDER"
require_file "$JAVA_BACKEND_FOLDER/Dockerfile"

for secret in ADMIN_EMAIL ADMIN_PASSWORD JAVA_DB_PASSWORD JAVA_DB_ROOT_PASSWORD; do
    warn_default_secret "$secret"
done

info "Java backend: $JAVA_BACKEND_FOLDER"
info "Listening:    127.0.0.1:$JAVA_PORT (public: $AUTH_PUBLIC_URL)"
info "Profile:      $JAVA_PROFILE"

# ============================================================
step "Compose env ($COMPOSE_ENV)"
# ============================================================

write_compose_env "$COMPOSE_ENV" \
    JAVA_BACKEND_FOLDER JAVA_PORT JAVA_PROFILE \
    JAVA_DB_NAME JAVA_DB_USER JAVA_DB_PASSWORD JAVA_DB_ROOT_PASSWORD \
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
Description=Design DaaS Java backend (users, OAuth, permissions)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$JAVA_DIR
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
step "Wait for the Java backend"
# ============================================================

# First start runs the DB migrations, so give it a while
URL="http://127.0.0.1:$JAVA_PORT/oauth2/user/token"
if ! wait_http "$URL"; then
    "${COMPOSE[@]}" logs --tail 50 backend || true
    die "Java backend did not answer after 5 min (logs: make java-logs)"
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
    warn "if you changed ADMIN_PASSWORD later, change it in the Java backend too."
fi

success "Java backend installed (logs: make java-logs)"
