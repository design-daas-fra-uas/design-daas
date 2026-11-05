#!/usr/bin/env bash
#
# Checks the running frontend the way a browser reaches it (see README.md):
# nginx on :8443 under the name from FRONTEND_PUBLIC_URL, its certificate,
# the page and deep links, /auth/ reaching the Java backend, and the backend
# URLs baked into the build. Changes nothing.
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

HOST="$(url_host "$FRONTEND_PUBLIC_URL")"
BASE="https://$HOST:8443"
# Reach nginx on this host whatever the name resolves to elsewhere
CURL=(curl -s --max-time 10 --resolve "$HOST:8443:127.0.0.1" --cacert /etc/nginx/ssl/daas-ca.crt)
code() { "${CURL[@]}" -o /dev/null -w '%{http_code}' "$@"; }

echo "Checking $BASE"

if systemctl is-active --quiet frontend.service; then ok "frontend.service running"; else fail "frontend.service not running"; fi
c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:5001/)"
if [[ "$c" == 200 ]]; then ok "container on 127.0.0.1:5001"; else fail "container on 127.0.0.1:5001: HTTP $c"; fi

# --cacert: fails unless the certificate is signed by the local CA and
# covers the name
c="$(code "$BASE/")"
if [[ "$c" == 200 ]]; then ok "page with a valid certificate for $HOST"; else fail "page $BASE/: HTTP $c (000 = TLS/certificate or connection error)"; fi

c="$(code "$BASE/login")"
if [[ "$c" == 200 ]]; then ok "deep link /login"; else fail "deep link /login: HTTP $c"; fi

# Any answer from Java (400/401/415...) proves the proxy; 502/504 do not
c="$(code -X POST "$BASE/auth/oauth2/user/token")"
if [[ "$c" =~ ^[1-4][0-9][0-9]$ ]]; then ok "/auth/ reaches the Java backend (HTTP $c)"; else fail "/auth/ -> HTTP $c (Java backend down? make java-status)"; fi

js="$("${CURL[@]}" "$BASE/" | grep -o 'static/js/main[^"]*\.js' | head -1)"
bundle="$("${CURL[@]}" "$BASE/$js")"
for v in DAAS_PUBLIC_URL AUTH_PUBLIC_URL OAUTH_CLIENT_ID; do
    if [[ -n "$js" ]] && grep -qF -- "${!v}" <<<"$bundle"; then
        ok "build uses $v=${!v}"
    else
        fail "build does not contain $v=${!v} (make frontend-install rebuilds it)"
    fi
done

if (( FAILED )); then
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
