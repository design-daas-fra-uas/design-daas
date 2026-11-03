#!/usr/bin/env bash
#
# Creates the self-signed nginx certificate in /etc/nginx/ssl if missing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

usage() { echo "Usage: $0 [-o <org-unit>] [-c <common-name>]" >&2; exit 1; }

ORGUNIT="pve"
CNAME="pve.cluster.local"
while getopts ":o:c:" o; do
    case "$o" in
        o) ORGUNIT="$OPTARG" ;;
        c) CNAME="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

SSL_DIR="/etc/nginx/ssl"
KEYOUT="$SSL_DIR/selfsigned.key"
CRTOUT="$SSL_DIR/selfsigned.crt"
SUBJECT="/C=DE/ST=HE/L=FFM/O=PVE/OU=$ORGUNIT/CN=$CNAME"

require_cmds openssl
mkdir -p "$SSL_DIR"

if [[ -f "$CRTOUT" && -f "$KEYOUT" ]]; then
    info "Certificate already present ($(openssl x509 -noout -subject -enddate -in "$CRTOUT" | tr '\n' ' '))"
    info "Delete $CRTOUT to generate a new one"
    exit 0
fi

info "Generating self-signed certificate: $SUBJECT"
run openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEYOUT" -out "$CRTOUT" -subj "$SUBJECT"
chmod 600 "$KEYOUT"
success "Certificate written to $CRTOUT"
