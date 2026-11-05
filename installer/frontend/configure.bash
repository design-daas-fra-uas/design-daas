#!/usr/bin/env bash
#
# Configures nginx for the frontend (see README.md):
#   - installs frontend.conf: :8443 -> the daas-frontend container
#     (127.0.0.1:5001), /auth/ -> Java backend (127.0.0.1:JAVA_PORT)
#   - its server name is the host of FRONTEND_PUBLIC_URL (installer/daas.env);
#     without an env file frontN.cluster.local (N = trailing digit of -h)
#   - adds that name to /etc/hosts when this host cannot resolve it
#
# Requires daas/configure.bash to have run first (nginx.conf with the
# upstream_front upstream, and the certificate that covers the name).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

usage() {
    cat <<EOF >&2
Usage: $0 -r <repo-folder> -h <hostname> [-e <env-file>] [-f <frontend-folder>]

Options:
    -r    Design DaaS repository folder
    -h    Host name (without an env file its trailing digit 1-3 selects frontN)
    -e    Stack env file (installer/daas.env): FRONTEND_PUBLIC_URL, JAVA_PORT
    -f    Frontend repository folder (unused, accepted for symmetry)
EOF
    exit 1
}

REPO_FOLDER=""
HOST_NAME=""
ENV_FILE=""
while getopts ":r:f:h:e:" o; do
    case "$o" in
        r) REPO_FOLDER="${OPTARG%/}" ;;
        f) ;;
        h) HOST_NAME="$OPTARG" ;;
        e) ENV_FILE="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$REPO_FOLDER" && -n "$HOST_NAME" ]] || usage

require_root
require_cmds sed grep getent hostname openssl nginx systemctl
require_dir "$REPO_FOLDER"

CONFIG_SOURCE="$REPO_FOLDER/installer/frontend/frontend.conf"
NGINX_CONFIG="/etc/nginx/sites-available/frontend.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/frontend.conf"
require_file "$CONFIG_SOURCE"
require_file /etc/nginx/ssl/selfsigned.crt

JAVA_PORT=8080
if [[ -n "$ENV_FILE" ]]; then
    load_stack_env "$ENV_FILE"
    FRONT_DOMAIN="$(url_host "$FRONTEND_PUBLIC_URL")"
    port="$(url_port "$FRONTEND_PUBLIC_URL")"
    [[ "$port" == 8443 ]] \
        || warn "FRONTEND_PUBLIC_URL uses port $port, nginx serves the frontend on 8443 (fine behind a proxy)"
else
    ID=0
    [[ "$HOST_NAME" =~ ([123])$ ]] && ID="${BASH_REMATCH[1]}"
    FRONT_DOMAIN="front${ID}.cluster.local"
fi
FRONT_IP="$(hostname -I | awk '{print $1}')"

info "Repository: $REPO_FOLDER"
info "Frontend:   https://$FRONT_DOMAIN:8443"
info "Java:       /auth/ -> 127.0.0.1:$JAVA_PORT"

# ============================================================
step "Name resolution ($FRONT_DOMAIN)"
# ============================================================

if getent hosts "$FRONT_DOMAIN" >/dev/null; then
    info "$FRONT_DOMAIN resolves to $(getent hosts "$FRONT_DOMAIN" | awk '{print $1; exit}')"
else
    [[ -n "$FRONT_IP" ]] || die "Could not determine the host IP (hostname -I is empty)"
    echo "$FRONT_IP $FRONT_DOMAIN" >> /etc/hosts
    success "Added to /etc/hosts: $FRONT_IP $FRONT_DOMAIN"
fi

if ! openssl x509 -noout -ext subjectAltName -in /etc/nginx/ssl/selfsigned.crt 2>/dev/null \
        | grep -qF "DNS:$FRONT_DOMAIN"; then
    warn "The certificate does not cover $FRONT_DOMAIN: run 'make daas-configure' first"
fi

# ============================================================
step "nginx"
# ============================================================

sed -e "s#front1.cluster.local#${FRONT_DOMAIN}#g" \
    -e "s#http://127.0.0.1:8080/#http://127.0.0.1:${JAVA_PORT}/#" \
    "$CONFIG_SOURCE" | write_file "$NGINX_CONFIG"
run ln -sfn "$NGINX_CONFIG" "$NGINX_ENABLED"

run nginx -t
enable_and_restart nginx

success "Frontend reachable at https://$FRONT_DOMAIN:8443 once frontend.service is running"
