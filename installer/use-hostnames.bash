#!/usr/bin/env bash
#
# Switches this host to the names pve.cluster.local (DaaS backend, :443) and
# front0.cluster.local (frontend + auth service, :8443):
#   - sets the host name and public URLs in installer/daas.env
#   - points both names at this host's IP in /etc/hosts
#   - re-runs the installer steps that use them: certificate + nginx + toml
#     (daas-configure), frontend nginx site, auth service and frontend
#     rebuilds (the URLs are baked in), backend restart
#
# Backups of daas.env and /etc/hosts are written next to them.
#
# Usage: sudo ./use-hostnames.bash [<ip>]   (default: first IP of hostname -I)

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.bash"

require_root
require_cmds make sed grep hostname

HOST_IP="${1:-$(hostname -I | awk '{print $1}')}"
[[ "$HOST_IP" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || die "Not an IPv4 address: '$HOST_IP'"

DAAS_HOST="pve.cluster.local"
FRONT_HOST="front0.cluster.local"
ENV_FILE="$DAAS_INSTALLER_DIR/daas.env"
STAMP="$(date +%Y%m%d%H%M%S)"
require_file "$ENV_FILE"

info "IP:       $HOST_IP"
info "DaaS:     https://$DAAS_HOST"
info "Frontend: https://$FRONT_HOST:8443"

# ============================================================
step "daas.env"
# ============================================================

# set_env KEY VALUE: replace KEY=... in ENV_FILE, or append it
set_env() {
    if grep -q "^$1=" "$ENV_FILE"; then
        sed -i "s#^$1=.*#$1=$2#" "$ENV_FILE"
    else
        echo "$1=$2" >> "$ENV_FILE"
    fi
    info "$1=$2"
}

run cp -p "$ENV_FILE" "$ENV_FILE.bak-$STAMP"
# FQDN = HOST_NAME.HOST_DOMAIN; HOST_NAME is also the Proxmox node name
set_env HOST_NAME           "pve"
set_env HOST_DOMAIN         "cluster.local"
set_env HOST_IP             "$HOST_IP"
set_env DAAS_PUBLIC_URL     "https://$DAAS_HOST"
set_env FRONTEND_PUBLIC_URL "https://$FRONT_HOST:8443"
set_env AUTH_PUBLIC_URL     "https://$FRONT_HOST:8443/auth"

# ============================================================
step "/etc/hosts"
# ============================================================

run cp -p /etc/hosts "/etc/hosts.bak-$STAMP"
# Drop every old line for the two names, then add one line for this IP
sed -i -E "/[[:space:]](${DAAS_HOST//./\\.}|${FRONT_HOST//./\\.})([[:space:]]|$)/d" /etc/hosts
echo "$HOST_IP $DAAS_HOST pve $FRONT_HOST front0" >> /etc/hosts
success "Added: $HOST_IP $DAAS_HOST pve $FRONT_HOST front0"

# ============================================================
step "Installer steps"
# ============================================================

cd "$DAAS_INSTALLER_DIR"
# daas-configure: toml values, certificate for both names, nginx site
run make ENV_FILE="$ENV_FILE" daas-configure
run make ENV_FILE="$ENV_FILE" frontend-configure
run make ENV_FILE="$ENV_FILE" auth-install
run make ENV_FILE="$ENV_FILE" frontend-install
run make ENV_FILE="$ENV_FILE" daas-restart

success "Done. On the computer with the browser:"
info "  1. Add to its hosts file: $HOST_IP $DAAS_HOST $FRONT_HOST"
info "  2. Trust /etc/nginx/ssl/selfsigned.crt (import it), or accept the"
info "     warning once on https://$DAAS_HOST/ and on https://$FRONT_HOST:8443/"
info "  3. Open https://$FRONT_HOST:8443/"
