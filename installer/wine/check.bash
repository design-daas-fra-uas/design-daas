#!/usr/bin/env bash
#
# Smoke test of the wine image: starts a test container, waits past
# pulseaudio's idle timeout, checks the desktop processes and ports and
# Wine (prefix, fonts, test app, running a Windows command), then removes
# the container.
#
# Usage: ./check.bash [<image>] [<container-name>]
#
# The DaaS agent in the container connects to RabbitMQ on the docker host
# like a real instance; it is gone again when the container is removed.

set -uo pipefail

IMAGE="${1:-wine}"
NAME="${2:-wine}"
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

# in_wine CMD: run CMD in the container with the environment the DaaS
# agent starts apps with (WINEPREFIX from the image, the desktop display)
in_wine() { docker exec -e DISPLAY=:0 "$NAME" bash -c "$1" 2>/dev/null; }

docker rm -f "$NAME" >/dev/null 2>&1
echo "Starting $NAME from $IMAGE"
docker run -d --rm --name "$NAME" "$IMAGE" >/dev/null || exit 1
trap 'docker rm -f "$NAME" >/dev/null 2>&1' EXIT
IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME")"
echo "Waiting ${WAIT}s (pulseaudio quits after 20s idle if misconfigured)"
sleep "$WAIT"

echo "Desktop ($NAME, $IP):"
expect_one "Xtigervnc"          "^/usr/bin/Xtigervnc"
expect_one "sshd"               "sshd: /usr/sbin/sshd"
expect_one "pulseaudio"         "^pulseaudio"
expect_one "DaaS agent"         "daas.runner_instance"
expect_one "qtile"              "qtile start"
expect_one "cupsd"              "^cupsd"
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

echo "Wine:"
version="$(in_wine 'wine --version')"
if [[ -n "$version" ]]; then ok "$version"; else fail "wine not found"; fi

if in_wine 'test -f "$WINEPREFIX/system.reg"'; then
    ok "prefix \$WINEPREFIX ready"
else
    fail "prefix \$WINEPREFIX not created"
fi

if in_wine 'ls "$WINEPREFIX/drive_c/windows/Fonts" | grep -qi "^arial.ttf$"'; then
    ok "corefonts (arial)"
else
    fail "corefonts missing"
fi

if in_wine 'test -f "$WINEPREFIX/drive_c/app.exe"'; then
    ok "test app C:\\app.exe"
else
    fail "test app missing"
fi

out="$(in_wine 'timeout 60 wine cmd /c echo daas-wine-ok' | tr -d '\r')"
if [[ "$out" == *daas-wine-ok* ]]; then ok "wine cmd /c echo runs"; else fail "wine cmd did not run"; fi

if (( FAILED )); then
    echo "Log of $NAME:"
    docker logs --tail 30 "$NAME" 2>&1
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
