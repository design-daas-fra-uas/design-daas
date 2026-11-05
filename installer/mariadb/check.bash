#!/usr/bin/env bash
#
# Smoke test of the mariadb image: starts a test container with its own
# empty data folder on 127.0.0.1:13306 (does not touch daas-0-mariadb), then
# checks the version and who may log in as root:
#   - the host, through the published port (like the DaaS backend): yes
#   - a container on the docker bridge (like a user instance): no
#   - the old public password my-secret-pw: no
# Removes the container and its data again. Passwords are never printed.
#
# Usage: ./check.bash [<image>] [<env-file>]     (run as root)

set -uo pipefail

IMAGE="${1:-daas-0-mariadb}"
ENV_FILE="${2:-$(dirname "$0")/../daas.env}"
NAME="daas-0-db-test"
PORT=13306
CLIENT="mariadb:11.4"
FAILED=0

ok()   { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }

PASSWORD="$(sed -n 's/^DAAS_DB_PASSWORD=//p' "$ENV_FILE" | tail -n1)"
[[ -n "$PASSWORD" ]] || { echo "DAAS_DB_PASSWORD is not set in $ENV_FILE"; exit 1; }

# sql NETWORK HOST PORT PASSWORD QUERY: run QUERY as root, print the result
# (the password goes in through the environment of the throwaway client
# container: never on the host's command line; the client ignores MYSQL_PWD)
sql() {
    PW="$4" Q="$5" docker run --rm --network "$1" -e PW -e Q "$CLIENT" \
        sh -c 'exec mariadb -h "$0" -P "$1" -uroot -p"$PW" -N -e "$Q"' "$2" "$3" 2>&1 \
        | grep -v '^WARNING: option --ssl-verify-server-cert'
}

DATA="$(mktemp -d)"
docker rm -f "$NAME" >/dev/null 2>&1
echo "Starting $NAME from $IMAGE (data in $DATA, port 127.0.0.1:$PORT)"
docker run -d --rm --name "$NAME" -p "127.0.0.1:$PORT:3306" -v "$DATA:/var/lib/mysql:rw" "$IMAGE" >/dev/null || exit 1
trap 'docker rm -f "$NAME" >/dev/null 2>&1; rm -rf "$DATA"' EXIT
IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME")"

echo "Waiting for the first start (up to 90s)"
for _ in $(seq 1 45); do
    docker exec "$NAME" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1 && break
    sleep 2
done

echo "Checks ($NAME, $IP):"
out="$(sql host 127.0.0.1 "$PORT" "$PASSWORD" 'SELECT VERSION()')"
if [[ "$out" == 11.4.* ]]; then ok "root login from the host via 127.0.0.1:$PORT (MariaDB $out)"; else fail "root login from the host: $out"; fi

out="$(sql bridge "$IP" 3306 "$PASSWORD" 'SELECT 1')"
if [[ "$out" == *"Access denied"* || "$out" == *"is not allowed to connect"* ]]; then
    ok "root login from the docker bridge (instances) refused"
else
    fail "root login from the docker bridge: $out"
fi

out="$(sql host 127.0.0.1 "$PORT" my-secret-pw 'SELECT 1')"
if [[ "$out" == *"Access denied"* ]]; then ok "old public password refused"; else fail "old public password: $out"; fi

hosts="$(sql host 127.0.0.1 "$PORT" "$PASSWORD" "SELECT GROUP_CONCAT(host ORDER BY host) FROM mysql.user WHERE user='root'")"
if [[ "$hosts" != *%* ]]; then ok "root accounts: $hosts"; else fail "root may log in from anywhere: $hosts"; fi

if (( FAILED )); then
    echo "Log of $NAME:"
    docker logs --tail 20 "$NAME" 2>&1
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
