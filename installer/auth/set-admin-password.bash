#!/usr/bin/env bash
#
# Sets the auth service's admin password to ADMIN_PASSWORD from the env file
# and revokes all tokens the admin was issued (see README.md). Use it after
# changing ADMIN_PASSWORD: the auth service only reads that setting when it
# creates the admin on its very first start, and it has no password-change
# function of its own.
#
# The BCrypt hash (cost 12, like the auth service's PasswordConfig) is made
# in a throwaway python container; the password only travels over stdin and
# is never printed or logged.
#
# Usage: ./set-admin-password.bash -e <env-file>     (run as root)
# Then:  make daas-configure && make daas-restart (the DaaS backend logs in
#        with the same password)

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

HASHER_IMAGE="python:3.12-slim"

ENV_FILE=""
while getopts ":e:" o; do
    case "$o" in
        e) ENV_FILE="$OPTARG" ;;
        *) echo "Usage: $0 -e <env-file>" >&2; exit 1 ;;
    esac
done
[[ -n "$ENV_FILE" ]] || { echo "Usage: $0 -e <env-file>" >&2; exit 1; }
require_root
require_cmds docker
load_stack_env "$ENV_FILE" >/dev/null
warn_default_secret ADMIN_PASSWORD
[[ "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._@+-]+$ ]] || die "Unexpected characters in ADMIN_EMAIL"
[[ -n "$(docker ps -q --filter name=^daas-auth-db$)" ]] || die "daas-auth-db is not running (make auth-start)"

step "BCrypt hash ($HASHER_IMAGE)"
hash="$(printf '%s' "$ADMIN_PASSWORD" | docker run --rm -i "$HASHER_IMAGE" sh -c \
    'pip -q install --root-user-action=ignore --disable-pip-version-check bcrypt >/dev/null 2>&1 &&
     python -c "import sys,bcrypt; print(bcrypt.hashpw(sys.stdin.read().encode(), bcrypt.gensalt(12, prefix=b\"2a\")).decode())"')"
[[ "$hash" =~ ^\$2a\$12\$[./A-Za-z0-9]{53}$ ]] || die "Could not create the password hash"
success "Hash created"

step "Admin $ADMIN_EMAIL in the auth service database"
result="$(docker exec -i daas-auth-db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot -N "$MARIADB_DATABASE"' <<SQL
SET @uid = (SELECT id FROM users WHERE email = '$ADMIN_EMAIL');
UPDATE users SET password = '$hash', failed_login_attempts = 0, locked_until = NULL WHERE id = @uid;
SELECT ROW_COUNT();
DELETE FROM access_tokens WHERE user_id = @uid;
SELECT ROW_COUNT();
DELETE FROM refresh_tokens WHERE user_id = @uid;
SELECT ROW_COUNT();
SQL
)"
unset hash
read -r updated access refresh <<<"$(echo $result)"
[[ "$updated" == 1 ]] || die "No admin $ADMIN_EMAIL in the auth service database"
success "Password set, $access access and $refresh refresh tokens revoked"

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST "http://127.0.0.1:$AUTH_PORT/oauth2/user/token" \
    --data-urlencode grant_type=password --data-urlencode "username=$ADMIN_EMAIL" \
    --data-urlencode "password@"<(printf '%s' "$ADMIN_PASSWORD") --data-urlencode scope=admin)"
[[ "$code" == 200 ]] || die "Login with the new password failed (HTTP $code)"
success "Admin logs in with ADMIN_PASSWORD. Next: make daas-configure && make daas-restart"
