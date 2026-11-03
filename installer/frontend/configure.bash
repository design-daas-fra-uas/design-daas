#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Configuration
# ============================================================

SERVICE_NAME="frontend"
DEFAULT_REPO_FOLDER="/home/design-daas"

export DEBIAN_FRONTEND=noninteractive
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no"

REPO_FOLDER="$DEFAULT_REPO_FOLDER"
FRONTEND_FOLDER=""
HOST_NAME=""

NGINX_CONFIG="/etc/nginx/sites-available/frontend.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/frontend.conf"

GITHUB_REPO="https://github.com/design-daas-fra-uas/design-daas.git"

# ============================================================
# Logging
# ============================================================

log() {
    local level="$1"
    shift

    printf '[%s] [%-7s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$level" \
        "$*"
}

info() {
    log "INFO" "$@"
}

success() {
    log "SUCCESS" "$@"
}

warn() {
    log "WARN" "$@" >&2
}

error() {
    log "ERROR" "$@" >&2
}

die() {
    error "$@"
    exit 1
}

# ============================================================
# Error handling
# ============================================================

on_error() {
    local exit_code=$?
    local line_number=$1

    error "Script failed at line ${line_number} (exit code: ${exit_code})"
    exit "$exit_code"
}

trap 'on_error $LINENO' ERR

# ============================================================
# Usage
# ============================================================

usage() {
    cat <<EOF
Usage:
    $0 -f <frontend-folder> -h <hostname> [-r <daas-repo>]

Options:
    -r    Design DaaS repository folder (default: $DEFAULT_REPO_FOLDER)
    -f    Frontend repository folder
    -h    Hostname

Example:
    $0 -r /home/design-daas -f /home/design-daas-frontend -h frontend1
EOF
    exit 1
}

# ============================================================
# Parse arguments
# ============================================================

while getopts ":r:f:h:" option; do
    case "$option" in
        r)
            REPO_FOLDER="$OPTARG"
            ;;
        f)
            FRONTEND_FOLDER="$OPTARG"
            ;;
        h)
            HOST_NAME="$OPTARG"
            ;;
        :)
            die "Option -$OPTARG requires an argument."
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND - 1))

if [[ -n "$*" ]]; then
    usage
fi

[[ -n "$REPO_FOLDER" ]] || usage
[[ -n "$FRONTEND_FOLDER" ]] || usage
[[ -n "$HOST_NAME" ]] || usage

# ============================================================
# Validate environment
# ============================================================

info "Starting frontend deployment"
info "Design DaaS repository: $REPO_FOLDER"
info "Frontend folder: $FRONTEND_FOLDER"
info "Hostname: $HOST_NAME"

if [[ "$EUID" -ne 0 ]]; then
    die "This script must be executed as root."
fi

for command in sed grep ln cp systemctl nginx date; do
    command -v "$command" >/dev/null 2>&1 \
        || die "Required command not found: $command"
done

[[ -d "$REPO_FOLDER" ]] \
    || die "Repository directory does not exist: $REPO_FOLDER"

[[ -d "$FRONTEND_FOLDER" ]] \
    || die "Frontend directory does not exist: $FRONTEND_FOLDER"

CONFIG_SOURCE="$REPO_FOLDER/installer/frontend/frontend.conf"

[[ -f "$CONFIG_SOURCE" ]] \
    || die "Nginx configuration not found: $CONFIG_SOURCE"

# ============================================================
# Determine frontend ID
# ============================================================

info "Determining frontend instance ID"

ID=0

if [[ "$HOST_NAME" =~ ([123])$ ]]; then
    ID="${BASH_REMATCH[1]}"
fi

FRONT_HOST="front${ID}"
FRONT_DOMAIN="${FRONT_HOST}.cluster.local"
FRONT_IP=$(hostname -I | awk '{print $1}')

info "Frontend ID: $ID"
info "Frontend hostname: $FRONT_DOMAIN"
info "Frontend IP: $FRONT_IP"

# ============================================================
# Configure /etc/hosts
# ============================================================

info "Configuring /etc/hosts"

if grep -Eq "^[[:space:]]*${FRONT_IP//./\\.}[[:space:]]+.*${FRONT_HOST}([[:space:]]|$)" /etc/hosts; then
    success "Host entry already exists"
else
    info "Adding host entry: $FRONT_IP $FRONT_DOMAIN $FRONT_HOST"

    echo "$FRONT_IP $FRONT_DOMAIN $FRONT_HOST" >> /etc/hosts

    success "Host entry added"
fi

# ============================================================
# Configure Nginx
# ============================================================

info "Deploying Nginx configuration"

TEMP_CONFIG=$(mktemp)

trap 'rm -f "${TEMP_CONFIG:-}"' EXIT

cp "$CONFIG_SOURCE" "$TEMP_CONFIG"

sed -i \
    "s#front1.cluster.local#${FRONT_DOMAIN}#g" \
    "$TEMP_CONFIG"

if ! cmp -s "$TEMP_CONFIG" "$NGINX_CONFIG" 2>/dev/null; then
    cp "$TEMP_CONFIG" "$NGINX_CONFIG"
    success "Nginx configuration updated"
else
    info "Nginx configuration is already up to date"
fi

# ============================================================
# Enable Nginx site
# ============================================================

info "Enabling Nginx site"

if [[ -L "$NGINX_ENABLED" ]] && [[ "$(readlink -f "$NGINX_ENABLED")" == "$NGINX_CONFIG" ]]; then
    info "Nginx site is already enabled"
else
    rm -f "$NGINX_ENABLED"
    ln -s "$NGINX_CONFIG" "$NGINX_ENABLED"
    success "Nginx site enabled"
fi

# ============================================================
# Validate and restart Nginx
# ============================================================

info "Validating Nginx configuration"

nginx -t || die "Nginx configuration validation failed"

info "Restarting Nginx"

systemctl restart nginx

systemctl is-active --quiet nginx \
    || die "Nginx failed to start"

success "Nginx restarted successfully"

# ============================================================
# Finished
# ============================================================

success "Frontend deployment completed successfully"

info "Repository: $GITHUB_REPO"
info "Frontend instance: $FRONT_HOST"
info "Hostname: $FRONT_DOMAIN"
info "IP address: $FRONT_IP"

