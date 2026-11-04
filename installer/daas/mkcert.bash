#!/usr/bin/env bash
#
# Creates the nginx TLS certificate in /etc/nginx/ssl:
#   - daas-ca.crt/.key: a local CA (created once, valid 10 years). Import
#     daas-ca.crt into the browser as a trusted authority once.
#   - selfsigned.crt/.key: the server certificate, signed by that CA, with
#     the requested names as subjectAltName (browsers ignore the CN).
# The server certificate is renewed if it is missing, not signed by the CA,
# lacks one of the names or expires within 30 days.

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
CAKEY="$SSL_DIR/daas-ca.key"
CACRT="$SSL_DIR/daas-ca.crt"
KEYOUT="$SSL_DIR/selfsigned.key"
CRTOUT="$SSL_DIR/selfsigned.crt"
SUBJECT="/C=DE/ST=HE/L=FFM/O=PVE/OU=$ORGUNIT/CN=$CNAME"
CA_SUBJECT="/C=DE/ST=HE/L=FFM/O=PVE/OU=$ORGUNIT/CN=Design DaaS local CA ($(hostname -s))"

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

# ============================================================
# Local CA
# ============================================================

if [[ -f "$CACRT" && -f "$CAKEY" ]]; then
    info "Local CA present: $CACRT"
else
    info "Generating local CA: $CA_SUBJECT"
    run openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CAKEY" -out "$CACRT" -subj "$CA_SUBJECT" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign"
    chmod 600 "$CAKEY"
    FORCE="yes"
    success "Local CA written to $CACRT"
fi

# ============================================================
# Server certificate
# ============================================================

# Prints the names the certificate is valid for, one per line (DNS:x / IP:x)
cert_sans() {
    openssl x509 -noout -ext subjectAltName -in "$CRTOUT" 2>/dev/null \
        | tail -n +2 | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/^IP Address:/IP:/'
}

# Prints why the server certificate must be renewed (empty: it is fine)
renew_reason() {
    [[ -f "$CRTOUT" && -f "$KEYOUT" ]] || { echo "missing"; return; }
    openssl verify -CAfile "$CACRT" "$CRTOUT" >/dev/null 2>&1 \
        || { echo "not signed by the local CA"; return; }
    openssl x509 -noout -checkend $((30 * 86400)) -in "$CRTOUT" >/dev/null \
        || { echo "expires within 30 days"; return; }
    local present entry missing=()
    present="$(cert_sans)"
    for entry in "${SAN_LIST[@]}"; do
        grep -qxF "$entry" <<<"$present" || missing+=("$entry")
    done
    (( ${#missing[@]} == 0 )) || echo "lacks ${missing[*]}"
}

reason="forced"
[[ -n "$FORCE" ]] || reason="$(renew_reason)"
if [[ -z "$reason" ]]; then
    info "Certificate already present ($(openssl x509 -noout -subject -enddate -in "$CRTOUT" | tr '\n' ' '))"
    info "Use -f to generate a new one"
    exit 0
fi

info "Generating server certificate ($reason): $SUBJECT ($SAN)"
CSR="$(mktemp)"
EXT="$(mktemp)"
trap 'rm -f "$CSR" "$EXT"' EXIT
run openssl req -nodes -newkey rsa:2048 -keyout "$KEYOUT" -out "$CSR" -subj "$SUBJECT"
cat > "$EXT" <<EOF
subjectAltName=$SAN
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
# 825 days is the longest validity browsers accept for server certificates
run openssl x509 -req -in "$CSR" -CA "$CACRT" -CAkey "$CAKEY" -CAcreateserial \
    -days 825 -sha256 -extfile "$EXT" -out "$CRTOUT"
chmod 600 "$KEYOUT"
success "Certificate written to $CRTOUT (import $CACRT into the browser)"
