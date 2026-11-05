#!/usr/bin/env bash
#
# Smoke test of the extensions image: starts a test container (no published
# ports, so it does not clash with the running daas-0-extensions), checks
# its services, prints a test page end to end the way the DaaS backend does
# (websocket -> printer -> PDF back over the websocket) and checks that bad
# input is rejected. Removes the container again.
#
# Usage: ./check.bash [<image>] [<container-name>]

set -uo pipefail

IMAGE="${1:-daas-0-extensions}"
NAME="${2:-daas-0-extensions-test}"
FAILED=0

ok()   { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }

# ws ID [FILE]: open the printer websocket as the backend does, wait for
# the printer, then print /etc/hosts on it, or with FILE: report FILE to the
# file API as a printed PDF. Prints the messages received (and the PDF size)
# until a file arrives or 30s pass
ws() {
    docker exec -i -e ID="$1" -e FAKE="${2:-}" -w /usr/src/app "$NAME" node - <<'EOF'
const WebSocket = require("ws");
const { execFile } = require("child_process");
const id = process.env.ID;
const ws = new WebSocket("ws://127.0.0.1:8010/vnc/printer?id=" + encodeURIComponent(id));
let size = 0;
const done = (msg) => { console.log(msg); process.exit(0); };
setTimeout(() => done("timeout"), 30000);
ws.on("error", (e) => done("ws-error " + e.message));
ws.on("close", () => done("closed"));
ws.on("message", (m) => {
  const d = JSON.parse(m);
  if (d.type === "status") {
    console.log("status " + d.status);
    if (d.status !== "printer is ready") return;
    if (process.env.FAKE)
      execFile("curl", ["-s", "-X", "POST", "-H", "Content-Type: application/json",
        "-d", JSON.stringify({ message: process.env.FAKE }),
        "http://127.0.0.1:8010/api/vnc/file"], () => setTimeout(() => done("no-file"), 2000));
    else
      execFile("lp", ["-d", id, "/etc/hosts"], () => {});
  } else if (d.type === "file-chunk") {
    size += Buffer.from(d.data, "base64").length;
  } else if (d.type === "file-end") {
    done("file " + d.name + " " + size);
  } else if (d.status) {
    done("status " + d.status);
  }
});
EOF
}

docker rm -f "$NAME" >/dev/null 2>&1
echo "Starting $NAME from $IMAGE"
docker run -d --rm --name "$NAME" "$IMAGE" >/dev/null || exit 1
trap 'docker rm -f "$NAME" >/dev/null 2>&1' EXIT

echo "Waiting for the printer server (up to 30s)"
for _ in $(seq 1 30); do
    docker exec "$NAME" sh -c 'echo > /dev/tcp/127.0.0.1/8010' 2>/dev/null && break
    docker exec "$NAME" bash -c 'exec 3<>/dev/tcp/127.0.0.1/8010' 2>/dev/null && break
    sleep 1
done

echo "Services:"
for p in "node server.js" "cupsd" "sshd"; do
    if docker exec "$NAME" pgrep -f "$p" >/dev/null; then ok "$p running"; else fail "$p not running"; fi
done
if docker exec "$NAME" bash -c 'exec 3<>/dev/tcp/127.0.0.1/631' 2>/dev/null; then ok "CUPS on :631"; else fail "CUPS on :631 not answering"; fi

echo "Print a test page (like the backend):"
out="$(ws checkuser)"
if grep -q "status printer is ready" <<<"$out"; then ok "printer checkuser created"; else fail "printer not created: $out"; fi
if grep -qE "^file .*\.pdf [1-9][0-9]*$" <<<"$out"; then ok "PDF sent back over the websocket ($(grep '^file' <<<"$out" | cut -d' ' -f3) bytes)"; else fail "no PDF received: $(tail -1 <<<"$out")"; fi

echo "Bad input is rejected:"
docker exec "$NAME" rm -f /tmp/injected
ws 'x;touch /tmp/injected' >/dev/null
if docker exec "$NAME" test -e /tmp/injected; then fail "printer id runs shell commands (id='x;touch /tmp/injected')"; else ok "printer id cannot run shell commands"; fi

# The server takes the session from the 5th path part: aim at an open
# session (checkuser) and let ".." lead to another file
docker exec "$NAME" sh -c 'cp /etc/hostname /tmp/victim'
out="$(ws checkuser /usr/src/app/files/checkuser/../../../../../tmp/victim)"
if docker exec "$NAME" test -e /tmp/victim && ! grep -q '^file' <<<"$out"; then
    ok "file API only takes printed PDFs"
else
    fail "file API sent and deleted /tmp/victim ($(tail -1 <<<"$out"))"
fi

if (( FAILED )); then
    echo "Log of $NAME:"
    docker logs --tail 30 "$NAME" 2>&1
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
