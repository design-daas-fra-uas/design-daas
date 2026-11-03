#!/usr/bin/env bash
#
# Installs the Design DaaS backend on the host:
#   - Python venv + TLS key for the backend (src/Makefile install)
#   - nginx, jq and docker-compose
#   - the daas systemd unit (enabled, but NOT started: run daas/configure.bash
#     and build the service images first, then `make daas-start`)

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

SERVICE_NAME="daas"
COMPOSE_VERSION="v2.24.0"
COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
COMPOSE_BIN="/usr/bin/docker-compose"

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

info "Repository: $REPO_FOLDER"

# ============================================================
step "Backend Python environment"
# ============================================================

run make -C "$REPO_FOLDER/src" install

# ============================================================
step "Host packages"
# ============================================================

apt_install nginx jq curl

if [[ -x "$COMPOSE_BIN" ]] && "$COMPOSE_BIN" version 2>/dev/null | grep -q "${COMPOSE_VERSION}"; then
    info "docker-compose ${COMPOSE_VERSION} already installed"
else
    info "Downloading docker-compose ${COMPOSE_VERSION}"
    run curl -fSL "$COMPOSE_URL" -o "$COMPOSE_BIN"
    chmod +x "$COMPOSE_BIN"
    success "Installed $("$COMPOSE_BIN" version)"
fi

# ============================================================
step "systemd unit: $SERVICE_NAME.service"
# ============================================================

write_file "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Design DaaS backend
Wants=pve-cluster.service pvedaemon.service ssh.service pve-storage.target
After=network.target pve-storage.target pve-cluster.service pvedaemon.service ssh.service nginx.service docker.service
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
enable_and_restart nginx

# dnsmasq serves DHCP on vmbr1, which the backend creates on its first start.
# Until then it may not come up, so only warn here.
run systemctl enable dnsmasq
if run systemctl restart dnsmasq && systemctl is-active --quiet dnsmasq; then
    success "Service running: dnsmasq"
else
    warn "dnsmasq is not running yet (vmbr1 may not exist until the backend has started once)"
fi

success "Backend installed. $SERVICE_NAME.service is enabled but not started."
info "Next: make daas-configure, make daas-services, then make daas-start"
