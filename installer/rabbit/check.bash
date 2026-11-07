#!/usr/bin/env bash
#
# Smoke test of the rabbit image: starts a test container (no published
# ports, so it does not clash with the running daas-0-rabbit), checks the
# broker, its settings and that it speaks AMQP, then removes the container.
#
# Usage: ./check.bash [<image>] [<container-name>]

set -uo pipefail

IMAGE="${1:-daas-0-rabbit}"
NAME="${2:-daas-0-rabbit-test}"
FAILED=0

ok()   { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }

# erl EXPR: evaluate an Erlang expression in the broker
erl() { docker exec "$NAME" rabbitmqctl -q eval "$1" 2>/dev/null; }

docker rm -f "$NAME" >/dev/null 2>&1
echo "Starting $NAME from $IMAGE"
docker run -d --rm --name "$NAME" "$IMAGE" >/dev/null || exit 1
trap 'docker rm -f "$NAME" >/dev/null 2>&1' EXIT
IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME")"

# Wait for the log line, not with rabbitmqctl: a CLI call before the broker
# is up writes its own Erlang cookie and every later CLI call is refused
echo "Waiting for the broker (up to 60s)"
for _ in $(seq 1 30); do
    docker logs "$NAME" 2>&1 | grep -q "Server startup complete" && break
    sleep 2
done

echo "Checks ($NAME, $IP):"
version="$(docker exec "$NAME" rabbitmq-diagnostics -q server_version 2>/dev/null)"
if [[ -n "$version" ]]; then ok "broker running (RabbitMQ $version)"; else fail "broker not running"; fi

hb="$(erl 'application:get_env(rabbit, heartbeat).')"
if [[ "$hb" == "{ok,3}" ]]; then ok "heartbeat 3s (rabbitmq.conf)"; else fail "heartbeat is $hb, expected {ok,3}"; fi

# The agents log in as guest from 172.17.0.x, not from localhost
lb="$(erl 'application:get_env(rabbit, loopback_users).')"
if [[ "$lb" == "{ok,[]}" ]]; then ok "guest may log in from other hosts"; else fail "loopback_users is $lb (guest only from localhost)"; fi

if docker exec "$NAME" rabbitmqctl -q authenticate_user guest guest >/dev/null 2>&1; then
    ok "user guest/guest"
else
    fail "guest/guest login rejected"
fi

# An AMQP 0-9-1 broker answers the protocol header with a Connection.Start
# frame: type 1 (method), channel 0
frame="$(timeout 5 bash -c "exec 3<>/dev/tcp/$IP/5672 && printf 'AMQP\x00\x00\x09\x01' >&3 && head -c 3 <&3 | od -An -tx1" 2>/dev/null | tr -d ' ')"
if [[ "$frame" == 010000 ]]; then ok "AMQP on $IP:5672"; else fail "AMQP on $IP:5672 not answering (got '$frame')"; fi

if (( FAILED )); then
    echo "Log of $NAME:"
    docker logs --tail 30 "$NAME" 2>&1
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
