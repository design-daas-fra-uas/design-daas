#!/usr/bin/env bash
#
# Configures nginx for the frontend:
#   - adds frontN.cluster.local to /etc/hosts (N = last digit of the hostname)
#   - installs frontend.conf (:8443 -> 127.0.0.1:5001) and reloads nginx
#
# Requires daas/configure.bash to have run first (nginx.conf with the
# upstream_front upstream and the self-signed certificate).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

usage() {
    cat <<EOF >&2
Usage: $0 -r <repo-folder> -f <frontend-folder> -h <hostname>

Options:
    -r    Design DaaS repository folder
    -f    Frontend repository folder
    -h    Host name (its trailing digit 1-3 selects frontN)

Example:
    $0 -r /root/design-daas -f /root/design-daas-application-frontend -h pve1
EOF
    exit 1
}

REPO_FOLDER=""
FRONTEND_FOLDER=""
HOST_NAME=""
while getopts ":r:f:h:" o; do
    case "$o" in
        r) REPO_FOLDER="${OPTARG%/}" ;;
        f) FRONTEND_FOLDER="${OPTARG%/}" ;;
        h) HOST_NAME="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$REPO_FOLDER" && -n "$FRONTEND_FOLDER" && -n "$HOST_NAME" ]] || usage

require_root
require_cmds sed grep ln cp systemctl nginx hostname
require_dir "$REPO_FOLDER"
require_dir "$FRONTEND_FOLDER"

CONFIG_SOURCE="$REPO_FOLDER/installer/frontend/frontend.conf"
NGINX_CONFIG="/etc/nginx/sites-available/frontend.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/frontend.conf"
require_file "$CONFIG_SOURCE"
require_file /etc/nginx/ssl/selfsigned.crt

ID=0
if [[ "$HOST_NAME" =~ ([123])$ ]]; then
    ID="${BASH_REMATCH[1]}"
fi
FRONT_HOST="front${ID}"
FRONT_DOMAIN="${FRONT_HOST}.cluster.local"
FRONT_IP="$(hostname -I | awk '{print $1}')"
[[ -n "$FRONT_IP" ]] || die "Could not determine the host IP (hostname -I is empty)"

info "Repository: $REPO_FOLDER"
info "Frontend:   $FRONTEND_FOLDER"
info "Instance:   $FRONT_DOMAIN ($FRONT_IP)"

# ============================================================
step "/etc/hosts"
# ============================================================

if grep -Eq "^[[:space:]]*${FRONT_IP//./\\.}[[:space:]]+.*${FRONT_HOST}([[:space:]]|$)" /etc/hosts; then
    info "Host entry already present"
else
    echo "$FRONT_IP $FRONT_DOMAIN $FRONT_HOST" >> /etc/hosts
    success "Added host entry: $FRONT_IP $FRONT_DOMAIN $FRONT_HOST"
fi

# ============================================================
step "nginx"
# ============================================================

sed -e "s#front1.cluster.local#${FRONT_DOMAIN}#g" "$CONFIG_SOURCE" | write_file "$NGINX_CONFIG"
run ln -sfn "$NGINX_CONFIG" "$NGINX_ENABLED"

run nginx -t
enable_and_restart nginx

success "Frontend reachable at https://$FRONT_DOMAIN:8443 once frontend.service is running"
