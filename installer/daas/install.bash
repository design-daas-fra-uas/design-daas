#!/usr/bin/env bash
#
# Installs the Design DaaS backend on the host:
#   - Python venv + TLS key for the backend (src/Makefile install)
#   - the daas systemd unit (enabled, but NOT started: run daas/configure.bash
#     and build the service images first, then `make daas-start`)
#
# The host packages come from deps/install.bash (make deps).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

SERVICE_NAME="daas"

usage() {
    cat <<EOF >&2
Usage: $0 -r <repo-folder>

Options:
    -r    Design DaaS repository folder
EOF
    exit 1
}

REPO_FOLDER=""
while getopts ":r:" o; do
    case "$o" in
        r) REPO_FOLDER="${OPTARG%/}" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$REPO_FOLDER" ]] || usage
require_root
require_dir "$REPO_FOLDER/src"
require_cmds docker docker-compose nginx dnsmasq jq curl python3

info "Repository: $REPO_FOLDER"

# ============================================================
step "Backend Python environment"
# ============================================================

run make -C "$REPO_FOLDER/src" install

# ============================================================
step "systemd unit: $SERVICE_NAME.service"
# ============================================================

write_file "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Design DaaS backend
Wants=pve-cluster.service pvedaemon.service ssh.service pve-storage.target java-backend.service
After=network.target pve-storage.target pve-cluster.service pvedaemon.service ssh.service nginx.service docker.service java-backend.service
Requires=nginx.service pveproxy.service docker.service

[Service]
Type=simple
ExecStart=$REPO_FOLDER/installer/$SERVICE_NAME/start.bash
ExecStop=$REPO_FOLDER/installer/$SERVICE_NAME/stop.bash
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

run systemctl daemon-reload
run systemctl enable "$SERVICE_NAME.service"

success "Backend installed. $SERVICE_NAME.service is enabled but not started."
info "Next: make daas-configure, make images, then make daas-restart"
