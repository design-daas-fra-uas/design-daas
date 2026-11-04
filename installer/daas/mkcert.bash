#!/usr/bin/env bash
#
# Creates the self-signed nginx certificate in /etc/nginx/ssl if missing, or
# if the existing one does not list the requested names as subjectAltName
# (browsers ignore the CN and only check the SAN).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

usage() { echo "Usage: $0 [-o <org-unit>] [-c <common-name>] [-a <alt-name>]... [-f]" >&2; exit 1; }

ORGUNIT="pve"
CNAME="pve.cluster.local"
ALT_NAMES=()
FORCE=""
while getopts ":o:c:a:f" o; do
    case "$o" in
        o) ORGUNIT="$OPTARG" ;;
        c) CNAME="$OPTARG" ;;
        a) ALT_NAMES+=("$OPTARG") ;;
        f) FORCE="yes" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

SSL_DIR="/etc/nginx/ssl"
KEYOUT="$SSL_DIR/selfsigned.key"
CRTOUT="$SSL_DIR/selfsigned.crt"
SUBJECT="/C=DE/ST=HE/L=FFM/O=PVE/OU=$ORGUNIT/CN=$CNAME"

# subjectAltName entries: the CN first, then -a names (IP addresses as IP:)
SAN_LIST=()
for name in "$CNAME" "${ALT_NAMES[@]}"; do
    if [[ "$name" =~ ^[0-9.]+$ || "$name" == *:* ]]; then
        SAN_LIST+=("IP:$name")
    else
        SAN_LIST+=("DNS:$name")
    fi
done
SAN="$(IFS=,; echo "${SAN_LIST[*]}")"

require_cmds openssl
mkdir -p "$SSL_DIR"

# Prints the names the certificate is valid for, one per line (DNS:x / IP:x)
cert_sans() {
    openssl x509 -noout -ext subjectAltName -in "$CRTOUT" 2>/dev/null \
        | tail -n +2 | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/^IP Address:/IP:/'
}

if [[ -z "$FORCE" && -f "$CRTOUT" && -f "$KEYOUT" ]]; then
    missing=()
    present="$(cert_sans)"
    for entry in "${SAN_LIST[@]}"; do
        grep -qxF "$entry" <<<"$present" || missing+=("$entry")
    done
    if (( ${#missing[@]} == 0 )); then
        info "Certificate already present ($(openssl x509 -noout -subject -enddate -in "$CRTOUT" | tr '\n' ' '))"
        info "Use -f to generate a new one"
        exit 0
    fi
    warn "Existing certificate lacks ${missing[*]}, generating a new one"
fi

info "Generating self-signed certificate: $SUBJECT ($SAN)"
run openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEYOUT" -out "$CRTOUT" -subj "$SUBJECT" \
    -addext "subjectAltName=$SAN" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "extendedKeyUsage=serverAuth"
chmod 600 "$KEYOUT"
success "Certificate written to $CRTOUT"
