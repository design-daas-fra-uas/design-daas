#!/usr/bin/env bash
#
# Builds the frontend image and installs frontend.service
# (docker-compose, published on 127.0.0.1:5001).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

SERVICE_NAME="frontend"
COMPOSE_FILE="docker-compose-pve.yml"

usage() {
    cat <<EOF >&2
Usage: $0 -f <frontend-folder> [-r <repo-folder>]

Options:
    -f    Frontend repository folder
    -r    Design DaaS repository folder (unused, accepted for symmetry)
EOF
    exit 1
}

FRONTEND_FOLDER=""
while getopts ":r:f:" o; do
    case "$o" in
        r) ;;
        f) FRONTEND_FOLDER="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$FRONTEND_FOLDER" ]] || usage
require_root
require_cmds docker-compose systemctl
require_dir "$FRONTEND_FOLDER"
FRONTEND_FOLDER="$(realpath "$FRONTEND_FOLDER")"

info "Frontend: $FRONTEND_FOLDER"

# ============================================================
step "Build frontend image"
# ============================================================

write_file "$FRONTEND_FOLDER/$COMPOSE_FILE" <<EOF
version: "3.3"
services:
  web:
    build:
      context: "."
      target: "server"
    container_name: "daas-frontend"
    restart: "always"
    ports:
      - "127.0.0.1:5001:80"
EOF

run docker-compose -f "$FRONTEND_FOLDER/$COMPOSE_FILE" --project-directory "$FRONTEND_FOLDER" build

# ============================================================
step "systemd unit: $SERVICE_NAME.service"
# ============================================================

write_file "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Design DaaS Frontend
After=docker.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$FRONTEND_FOLDER
ExecStart=/usr/bin/docker-compose -f $COMPOSE_FILE up
ExecStop=/usr/bin/docker-compose -f $COMPOSE_FILE down
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

run systemctl daemon-reload
enable_and_restart "$SERVICE_NAME.service"

success "Frontend installed (logs: journalctl -u $SERVICE_NAME -f)"
