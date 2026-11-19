#!/usr/bin/env bash
#
# Installs the auth service (users, OAuth tokens, permissions) as
# daas-auth.service (docker-compose, 127.0.0.1:AUTH_PORT). Its data lives in
# the DaaS PostgreSQL (daas-0-postgres), database AUTH_DB_NAME: this script
# starts that container if needed and creates the database and AUTH_DB_USER
# there.
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

for secret in ADMIN_EMAIL ADMIN_PASSWORD AUTH_DB_PASSWORD; do
    warn_default_secret "$secret"
done
[[ "$AUTH_DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || die "AUTH_DB_NAME may only contain letters, digits and _"
[[ "$AUTH_DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || die "AUTH_DB_USER may only contain letters, digits and _"

info "auth service: $AUTH_FOLDER"
info "Listening:    127.0.0.1:$AUTH_PORT (public: $AUTH_PUBLIC_URL)"
info "Profile:      $AUTH_PROFILE"
info "Database:     $AUTH_DB_NAME in $DAAS_DB_CONTAINER"

# ============================================================
step "Database $AUTH_DB_NAME in $DAAS_DB_CONTAINER"
# ============================================================

# The DaaS backend starts it too; on a fresh install it is not running yet
if [[ -z "$(docker ps -q --filter "name=^$DAAS_DB_CONTAINER$")" ]]; then
    run "$DAAS_INSTALLER_DIR/service.bash" start db
fi
wait_daas_db || die "$DAAS_DB_CONTAINER does not accept logins (make db-logs)"

# Own user that owns its database and may connect to no other (the image
# takes CONNECT on mergedb away from everyone else). pg_hba.conf lets it log
# in from the docker host only. The password is set on every run, so a
# changed AUTH_DB_PASSWORD takes effect with auth-install.
# \gexec runs the CREATE only when the SELECT returns it (no IF NOT EXISTS
# for databases in PostgreSQL).
daas_db_sql <<SQL
SELECT 'CREATE ROLE "$AUTH_DB_USER" LOGIN'
    WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$AUTH_DB_USER')\\gexec
ALTER ROLE "$AUTH_DB_USER" WITH LOGIN PASSWORD $(sql_string "$AUTH_DB_PASSWORD");
SELECT 'CREATE DATABASE "$AUTH_DB_NAME" OWNER "$AUTH_DB_USER"'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$AUTH_DB_NAME')\\gexec
REVOKE CONNECT, TEMPORARY ON DATABASE "$AUTH_DB_NAME" FROM PUBLIC;
SQL
success "Database $AUTH_DB_NAME, user $AUTH_DB_USER (logs in from $DAAS_DB_CLIENT_HOST)"

# ============================================================
step "Compose env ($COMPOSE_ENV)"
# ============================================================

write_compose_env "$COMPOSE_ENV" \
    AUTH_FOLDER AUTH_PORT AUTH_PROFILE \
    AUTH_DB_NAME AUTH_DB_USER AUTH_DB_PASSWORD \
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
# Its database daas-0-postgres is started by daas.service
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
