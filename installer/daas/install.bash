#!/usr/bin/env bash
#
# Installs the Design DaaS backend on the host:
#   - Python venv + TLS key for the backend (src/Makefile install), only
#     when there is no venv yet (daas-reinstall deletes it first)
#   - the daas systemd unit (enabled, but NOT started: run daas/configure.bash
#     and build the service images first, then `make daas-start`)
#
# Safe to run again: it only rewrites the unit (applied at the next restart).
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

# src/Makefile install deletes and rebuilds the venv; do not pull it away
# under a running backend
if [[ -x "$REPO_FOLDER/src/.venv/bin/python3" ]]; then
    # A newer version may need more packages: install what is missing
    # (VENV_INST in src/Makefile), keep the rest as it is
    packages="$(MAKEFLAGS= MAKELEVEL= make -s --no-print-directory -C "$REPO_FOLDER/src" --eval 'print-venv-packages: ; @echo $(VENV_INST)' print-venv-packages)"
    # shellcheck disable=SC2086
    run "$REPO_FOLDER/src/.venv/bin/pip" install --quiet --disable-pip-version-check $packages
    info "Kept the existing venv, added missing packages (make daas-reinstall rebuilds it)"
else
    run make -C "$REPO_FOLDER/src" install
fi

# ============================================================
step "systemd unit: $SERVICE_NAME.service"
# ============================================================

write_file "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Design DaaS backend
# Wants, not Requires: restarting nginx or pveproxy (configure, certificate,
# Proxmox updates) must not restart the backend and its service containers.
# Docker is required: the service containers stop with it anyway.
Wants=nginx.service pveproxy.service pve-cluster.service pvedaemon.service pve-storage.target daas-auth.service
After=network-online.target nginx.service pveproxy.service pve-cluster.service pvedaemon.service pve-storage.target docker.service daas-auth.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$REPO_FOLDER/src
ExecStart=$REPO_FOLDER/installer/$SERVICE_NAME/start.bash
# Stop: SIGTERM to the backend only (it then stops its service
# containers), everything left after TimeoutStopSec is killed
KillMode=mixed
TimeoutStopSec=60
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

run systemctl daemon-reload
# reenable: also drops links of older units (WantedBy=getty.target)
run systemctl reenable "$SERVICE_NAME.service"

success "Backend installed. $SERVICE_NAME.service is enabled but not started."
info "Next: make daas-configure, make images, then make daas-restart"
