#!/usr/bin/env bash
#
# ExecStop of daas.service: stops the backend process.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

PIDS="$(pgrep -f "python3 main.py" || true)"
if [[ -z "$PIDS" ]]; then
    info "Backend is not running"
    exit 0
fi

info "Stopping backend (PID: $(echo $PIDS))"
# shellcheck disable=SC2086
kill $PIDS

# Give the backend time to stop its service containers
for _ in $(seq 1 30); do
    pgrep -f "python3 main.py" >/dev/null || { success "Backend stopped"; exit 0; }
    sleep 1
done
warn "Backend still running after 30s"
