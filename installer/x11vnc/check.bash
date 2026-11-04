#!/usr/bin/env bash
#
# Smoke test of the x11vnc image: starts a test container, waits past
# pulseaudio's idle timeout, checks every process of entrypoint.bash and the
# VNC port, then removes the container.
#
# Usage: ./check.bash [<image>] [<container-name>]
#
# The DaaS agent in the container connects to RabbitMQ on the docker host
# like a real instance; it is gone again when the container is removed.

set -uo pipefail

IMAGE="${1:-x11vnc}"
NAME="${2:-x11vnc}"
WAIT=25
FAILED=0

ok()   { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }

# count PATTERN: number of processes in the container matching PATTERN
count() {
    local n
    n="$(docker exec "$NAME" pgrep -fc "$1" 2>/dev/null)"
    echo "${n:-0}"
}

expect_one() {
    local n
    n="$(count "$2")"
    if [[ "$n" == 1 ]]; then ok "$1"; else fail "$1: $n processes (expected 1)"; fi
}

docker rm -f "$NAME" >/dev/null 2>&1
echo "Starting $NAME from $IMAGE"
docker run -d --rm --name "$NAME" "$IMAGE" >/dev/null || exit 1
trap 'docker rm -f "$NAME" >/dev/null 2>&1' EXIT
IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME")"
echo "Waiting ${WAIT}s (pulseaudio quits after 20s idle if misconfigured)"
sleep "$WAIT"

echo "Checks ($NAME, $IP):"
expect_one "Xtigervnc"         "^/usr/bin/Xtigervnc"
expect_one "sshd"              "sshd: /usr/sbin/sshd"
expect_one "pulseaudio"        "^pulseaudio"
expect_one "DaaS agent"        "daas.runner_instance"
expect_one "qtile"             "qtile start"
expect_one "cupsd"             "^cupsd"
expect_one "mic listener :8080" "^nc -l -p 8080"

if docker exec "$NAME" pactl list short sinks 2>/dev/null | grep -q virtual_speaker; then
    ok "pulseaudio sink virtual_speaker"
else
    fail "pulseaudio sink virtual_speaker missing"
fi

# A VNC server greets with "RFB 003.00x"
banner="$(timeout 3 bash -c "exec 3<>/dev/tcp/$IP/5900 && head -c 12 <&3" 2>/dev/null)"
if [[ "$banner" == RFB* ]]; then ok "VNC on $IP:5900 ($banner)"; else fail "VNC on $IP:5900 not answering"; fi

if timeout 3 bash -c "exec 3<>/dev/tcp/$IP/22" 2>/dev/null; then ok "ssh on $IP:22"; else fail "ssh on $IP:22 not answering"; fi

if (( FAILED )); then
    echo "Log of $NAME:"
    docker logs --tail 30 "$NAME" 2>&1
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
