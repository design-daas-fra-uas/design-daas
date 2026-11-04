#!/usr/bin/env bash
#
# Smoke test of the guacd image: starts a test container (no published
# ports, so it does not clash with the running daas-0-guacd), checks guacd
# and asks it over the Guacamole protocol for every protocol DaaS uses,
# then removes the container.
#
# Usage: ./check.bash [<image>] [<container-name>]

set -uo pipefail

IMAGE="${1:-daas-0-guacd}"
NAME="${2:-daas-0-guacd-test}"
FAILED=0

ok()   { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }

# select PROTOCOL: send the handshake's first instruction ("select") and
# print guacd's answer, which is "args" with the protocol's parameters
select_protocol() {
    local p="$1"
    timeout 5 bash -c "exec 3<>/dev/tcp/$IP/4822 && printf '6.select,%s.%s;' ${#p} $p >&3 && head -c 40 <&3" 2>/dev/null
}

docker rm -f "$NAME" >/dev/null 2>&1
echo "Starting $NAME from $IMAGE"
docker run -d --rm --name "$NAME" "$IMAGE" >/dev/null || exit 1
trap 'docker rm -f "$NAME" >/dev/null 2>&1' EXIT
IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME")"
sleep 3

echo "Checks ($NAME, $IP):"
version="$(docker exec "$NAME" guacd -v 2>/dev/null)"
if [[ -n "$version" ]]; then ok "$version"; else fail "guacd not found"; fi

# guacd must be PID 1: when it dies the container stops and the backend
# notices, instead of a container that runs without guacd
pid1="$(docker exec "$NAME" cat /proc/1/cmdline 2>/dev/null | tr '\0' ' ')"
if [[ "$pid1" == guacd* ]]; then ok "guacd is PID 1"; else fail "PID 1 is '$pid1', not guacd"; fi

# VNC: container instances, RDP: Windows VMs, SSH: terminals
for p in vnc rdp ssh; do
    answer="$(select_protocol "$p")"
    if [[ "$answer" == 4.args,* ]]; then ok "protocol $p (${answer:0:28}...)"; else fail "protocol $p: no args answer (got '$answer')"; fi
done

# RDP printing converts the print job with ghostscript
if docker exec "$NAME" sh -c 'command -v gs' >/dev/null 2>&1; then ok "ghostscript (RDP printing)"; else fail "ghostscript missing"; fi

if (( FAILED )); then
    echo "Log of $NAME:"
    docker logs --tail 30 "$NAME" 2>&1
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
