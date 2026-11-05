#!/usr/bin/env bash
#
# Checks the running Java backend (see README.md): service and containers,
# the token endpoint, the admin login (directly as the DaaS backend uses it,
# and through nginx /auth/ as the frontend uses it), its data volumes, and
# that user instances cannot reach it directly. Changes nothing; the admin
# password is never printed.
#
# Usage: ./check.bash -e <env-file>     (run as root)

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"
set +e

ENV_FILE=""
while getopts ":e:" o; do
    case "$o" in
        e) ENV_FILE="$OPTARG" ;;
        *) echo "Usage: $0 -e <env-file>" >&2; exit 1 ;;
    esac
done
[[ -n "$ENV_FILE" ]] || { echo "Usage: $0 -e <env-file>" >&2; exit 1; }
require_root
load_stack_env "$ENV_FILE" >/dev/null

FAILED=0
ok()   { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }

DIRECT="http://127.0.0.1:$JAVA_PORT"
AUTH_HOST="$(url_host "$AUTH_PUBLIC_URL")"
AUTH_PORT="$(url_port "$AUTH_PUBLIC_URL")"

# login URL [CURL-ARGS...]: HTTP code of an admin password login at URL
login() {
    local url="$1"
    shift
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" -X POST "$url/oauth2/user/token" \
        --data-urlencode grant_type=password --data-urlencode "username=$ADMIN_EMAIL" \
        --data-urlencode "password=$ADMIN_PASSWORD" --data-urlencode scope=admin
}

echo "Checking the Java backend on 127.0.0.1:$JAVA_PORT and $AUTH_PUBLIC_URL"

if systemctl is-active --quiet java-backend.service; then ok "java-backend.service running"; else fail "java-backend.service not running (make java-logs)"; fi
for c in daas-java-backend daas-java-db; do
    state="$(docker inspect -f '{{.State.Status}}{{if .State.Health}} {{.State.Health.Status}}{{end}}' "$c" 2>/dev/null)"
    if [[ "$state" == running* && "$state" != *unhealthy* ]]; then ok "container $c ($state)"; else fail "container $c: ${state:-missing}"; fi
done

c="$(login "$DIRECT")"
if [[ "$c" == 200 ]]; then
    ok "admin login on $DIRECT (as the DaaS backend)"
elif [[ "$c" == 400 || "$c" == 401 ]]; then
    fail "admin login on $DIRECT: HTTP $c. ADMIN_PASSWORD is only used on the very first start; change it in the Java backend too"
else
    fail "admin login on $DIRECT: HTTP $c"
fi

c="$(login "$AUTH_PUBLIC_URL" --cacert /etc/nginx/ssl/daas-ca.crt --resolve "$AUTH_HOST:$AUTH_PORT:127.0.0.1")"
if [[ "$c" == 200 ]]; then ok "admin login on $AUTH_PUBLIC_URL (as the frontend, through nginx)"; else fail "admin login on $AUTH_PUBLIC_URL: HTTP $c (502 = Java down, 000 = TLS/nginx)"; fi

for v in daas-java_db-data daas-java_keys; do
    if docker volume inspect "$v" >/dev/null 2>&1; then ok "volume $v"; else fail "volume $v missing"; fi
done

# User instances live on the default docker bridge; they must not reach Java
ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' daas-java-backend 2>/dev/null)"
probe=""
for c in $(docker ps -q --filter network=bridge); do
    docker exec "$c" sh -c 'command -v bash' >/dev/null 2>&1 && { probe="$c"; break; }
done
if [[ -z "$probe" || -z "$ip" ]]; then
    info "No container on the default bridge to test isolation from"
elif docker exec "$probe" sh -c "timeout 3 bash -c 'exec 3<>/dev/tcp/$ip/8080'" >/dev/null 2>&1; then
    fail "Java container $ip:8080 is reachable from containers on the default bridge"
else
    ok "not reachable from the default docker bridge (instances)"
fi

if (( FAILED )); then
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
