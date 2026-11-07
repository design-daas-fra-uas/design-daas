#!/usr/bin/env bash
#
# Checks the running DaaS backend (see README.md): the service and its
# process, the public address through nginx with a valid certificate, that
# the backend itself is only reachable through nginx, the service
# containers, TLS versions, and that restarting nginx cannot take the
# backend down. Changes nothing.
#
# Usage: ./check.bash -e <env-file>     (run as root)

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"
set +e
# A check that finds nothing is not an installer error: no error trap here
trap - ERR

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

HOST="$(url_host "$DAAS_PUBLIC_URL")"
PORT="$(url_port "$DAAS_PUBLIC_URL")"
SERVICES=(daas-0-guacd daas-0-mariadb daas-0-rabbit daas-0-extensions)

echo "Checking $DAAS_PUBLIC_URL"

if systemctl is-active --quiet daas.service; then ok "daas.service running"; else fail "daas.service not running (make daas-logs)"; fi
pid="$(systemctl show -p MainPID --value daas.service)"
cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
if [[ "$cmd" == */.venv/bin/python3\ main.py* ]]; then
    ok "main process is the backend ($cmd)"
else
    fail "main process is '$cmd', not the venv's python3 main.py (old unit? make daas-install)"
fi

requires="$(systemctl show -p Requires --value daas.service)"
if [[ " $requires " == *" nginx.service "* || " $requires " == *" pveproxy.service "* ]]; then
    fail "daas.service Requires nginx/pveproxy: restarting them restarts the backend (make daas-install)"
else
    ok "restarting nginx or pveproxy does not restart the backend"
fi

# Any answer from the backend proves the chain (GET / gives 405);
# --cacert: also fails when the certificate does not fit the name
c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --cacert /etc/nginx/ssl/daas-ca.crt \
    --resolve "$HOST:$PORT:127.0.0.1" "https://$HOST:$PORT/")"
if [[ "$c" =~ ^[1-4][0-9][0-9]$ ]]; then
    ok "$DAAS_PUBLIC_URL answers through nginx with a valid certificate (HTTP $c)"
else
    fail "$DAAS_PUBLIC_URL: HTTP $c (000 = TLS/certificate or connection error, 502 = backend down)"
fi

listen="$(ss -ltnH 'sport = :5000' | awk '{print $4}' | sort -u | tr '\n' ' ')"
if [[ "$listen" == "127.0.0.1:5000 " ]]; then
    ok "backend listens on 127.0.0.1:5000 only"
else
    fail "backend listens on '${listen:-nothing}' (expected 127.0.0.1:5000 only; make daas-configure)"
fi

# The database the backend is configured for (db.toml + config/local)
dbtype="$(cd "$DAAS_INSTALLER_DIR/../src" && python3 -I -c '
import sys; sys.path.insert(0, ".")
from app.qweb.common.tomlfile import read_toml_with_local
db = read_toml_with_local("config/db.toml")["db"]; print(db["db_type"], db["db_name"])' 2>/dev/null)"
read -r dbtype dbname <<<"$dbtype"
if [[ "$dbtype" == mariadb ]]; then
    n="$(docker exec daas-0-mariadb sh -c "MYSQL_PWD=\"\$MARIADB_ROOT_PASSWORD\" mariadb -uroot -N -e 'SELECT COUNT(*) FROM \`$dbname\`.daas_objects'" 2>/dev/null)"
    if [[ "$n" =~ ^[0-9]+$ ]]; then ok "database: MariaDB $dbname ($n objects)"; else fail "database: MariaDB $dbname not readable (make db-logs)"; fi
else
    ok "database: $dbtype ($dbname)"
fi

for s in "${SERVICES[@]}"; do
    if [[ -n "$(docker ps -q --filter "name=^$s$")" ]]; then ok "service container $s"; else fail "service container $s not running"; fi
done

for v in tls1_1:refused tls1_2:accepted tls1_3:accepted; do
    proto="${v%%:*}" want="${v##*:}"
    if echo | timeout 5 openssl s_client -connect "127.0.0.1:$PORT" -servername "$HOST" "-$proto" 2>/dev/null \
            | grep -q 'Cipher is [A-Z]'; then got=accepted; else got=refused; fi
    if [[ "$got" == "$want" ]]; then ok "${proto/_/.} $got"; else fail "${proto/_/.} $got (expected $want)"; fi
done

if (( FAILED )); then
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
