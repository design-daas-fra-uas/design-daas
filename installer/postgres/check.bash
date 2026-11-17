#!/usr/bin/env bash
#
# Smoke test of the postgres image: starts a test container with its own
# empty data folder on 127.0.0.1:15432 (does not touch daas-0-postgres), then
# checks the version, the database mergedb and who may log in:
#   - the host, through the published port (like the DaaS backend): yes
#   - a container on the docker bridge (like a user instance): no
#   - a wrong password: no
# Removes the container and its data again. Passwords are never printed.
#
# Usage: ./check.bash [<image>] [<env-file>]     (run as root)

set -uo pipefail

IMAGE="${1:-daas-0-postgres}"
ENV_FILE="${2:-$(dirname "$0")/../daas.env}"
NAME="daas-0-db-test"
PORT=15432
CLIENT="postgres:18"
FAILED=0

ok()   { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }

PASSWORD="$(sed -n 's/^DAAS_DB_PASSWORD=//p' "$ENV_FILE" | tail -n1)"
[[ -n "$PASSWORD" ]] || { echo "DAAS_DB_PASSWORD is not set in $ENV_FILE"; exit 1; }

# sql NETWORK HOST PORT PASSWORD QUERY: run QUERY as postgres in mergedb,
# print the result (the password goes in through the environment of the
# throwaway client container: never on the host's command line)
sql() {
    PGPASSWORD="$4" Q="$5" docker run --rm --network "$1" -e PGPASSWORD -e Q "$CLIENT" \
        sh -c 'exec psql -h "$0" -p "$1" -U postgres -d mergedb -tA -c "$Q"' "$2" "$3" 2>&1
}

DATA="$(mktemp -d)"
# The server runs as user postgres and must get into its folder below this one
chmod 755 "$DATA"
docker rm -f "$NAME" >/dev/null 2>&1
echo "Starting $NAME from $IMAGE (data in $DATA, port 127.0.0.1:$PORT)"
docker run -d --rm --name "$NAME" -p "127.0.0.1:$PORT:5432" -v "$DATA:/var/lib/postgresql:rw" "$IMAGE" >/dev/null || exit 1
trap 'docker rm -f "$NAME" >/dev/null 2>&1; rm -rf "$DATA"' EXIT
IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME")"

# The first start runs initdb and restarts the server once: wait for the
# final one (it listens on TCP, the temporary one only on the socket)
echo "Waiting for the first start (up to 90s)"
for _ in $(seq 1 45); do
    docker exec "$NAME" pg_isready -h 127.0.0.1 -q 2>/dev/null && break
    sleep 2
done

echo "Checks ($NAME, $IP):"
out="$(sql host 127.0.0.1 "$PORT" "$PASSWORD" 'SHOW server_version')"
if [[ "$out" == 18.* ]]; then ok "login from the host via 127.0.0.1:$PORT (PostgreSQL $out, database mergedb)"; else fail "login from the host: $out"; fi

out="$(sql bridge "$IP" 5432 "$PASSWORD" 'SELECT 1')"
if [[ "$out" == *"rejects connection"* ]]; then
    ok "login from the docker bridge (instances) refused"
else
    fail "login from the docker bridge: $out"
fi

out="$(sql host 127.0.0.1 "$PORT" wrong-password 'SELECT 1')"
if [[ "$out" == *"password authentication failed"* ]]; then ok "wrong password refused"; else fail "wrong password: $out"; fi

if (( FAILED )); then
    echo "Log of $NAME:"
    docker logs --tail 20 "$NAME" 2>&1
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
