#!/usr/bin/env bash
#
# Configures the Design DaaS backend for this host:
#   - sets hostname / IP values in src/config/*.toml
#   - installs the nginx config + a self-signed certificate
#   - seeds src/data from src/data_template
#
# Values are set by key name, so the script can be run again with other
# values (it no longer depends on placeholder strings being present).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

usage() {
    cat <<EOF >&2
Usage: $0 -r <repo-folder> -h <hostname> -d <domain> [-i <ip-part>] [-s <standalone>] [-n <device>]

Options:
    -r    Design DaaS repository folder
    -h    Host name (e.g. pve1)
    -d    Domain (e.g. daas-design.de)
    -i    Last octet of this host's IP in the DaaS networks (default: 1)
    -s    Non-empty (e.g. "yes") for a standalone host without uplink bridge
    -n    Network device bridged into vmbr0 (default: enp0s4)
EOF
    exit 1
}

REPO_FOLDER=""
HOST_NAME=""
DOMAIN_NAME=""
IP_PART=1
STANDALONE=""
DEVICE_NAME="enp0s4"
while getopts ":r:h:d:i:s:n:" o; do
    case "$o" in
        r) REPO_FOLDER="${OPTARG%/}" ;;
        h) HOST_NAME="$OPTARG" ;;
        d) DOMAIN_NAME="$OPTARG" ;;
        i) IP_PART="$OPTARG" ;;
        s) STANDALONE="$OPTARG" ;;
        n) DEVICE_NAME="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$REPO_FOLDER" && -n "$HOST_NAME" && -n "$DOMAIN_NAME" ]] || usage
[[ "$IP_PART" =~ ^[0-9]+$ ]] && (( IP_PART >= 1 && IP_PART <= 254 )) \
    || die "Invalid IP part '$IP_PART' (expected 1-254)"
if (( (IP_PART >= 50 && IP_PART <= 75) || (IP_PART >= 100 && IP_PART <= 104) )); then
    die "IP part $IP_PART collides with the dnsmasq DHCP addresses (.50-.75, .100-.104) on vmbr1"
fi

require_root
require_cmds sed grep openssl nginx systemctl
require_dir "$REPO_FOLDER/src/config"

FQDN="$HOST_NAME.$DOMAIN_NAME"
CFG_FOLDER="$REPO_FOLDER/src/config"
NGINX_SITE="/etc/nginx/sites-available/daas.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/daas.conf"

info "Repository:  $REPO_FOLDER"
info "Host:        $FQDN"
info "IP part:     $IP_PART"
info "Standalone:  ${STANDALONE:-no}"
info "Device:      $DEVICE_NAME"

# ============================================================
step "Backend config ($CFG_FOLDER)"
# ============================================================

set_toml_value "$CFG_FOLDER/qweb.toml"      hostip              "$FQDN"
set_toml_value "$CFG_FOLDER/proxy.toml"     viewer_host         "$FQDN"
set_toml_value "$CFG_FOLDER/vm.toml"        node                "$HOST_NAME"
set_toml_value "$CFG_FOLDER/vm.toml"        hostIp              "192.168.123.$IP_PART"
set_toml_value "$CFG_FOLDER/vm.toml"        bridge_cidr_daas    "192.168.123.$IP_PART/24"
set_toml_value "$CFG_FOLDER/vm.toml"        bridge_cidr_inst    "192.168.223.$IP_PART/24"
set_toml_value "$CFG_FOLDER/vm.toml"        bridge_cidr_ceph    "192.168.100.$IP_PART/24"
set_toml_value "$CFG_FOLDER/vm.toml"        bridge_cidr_cluster "192.168.200.$IP_PART/24"
set_toml_value "$CFG_FOLDER/container.toml" host                "192.168.123.$IP_PART"

# The backend only creates bridges that are missing, so an existing bridge
# with another address keeps it and no longer matches the config.
check_bridge() {
    local bridge="$1" wanted="$2" current
    current="$(ip -4 -o addr show dev "$bridge" 2>/dev/null | awk '{print $4; exit}' || true)"
    if [[ -z "$current" ]]; then
        info "$bridge does not exist yet (the backend creates it as $wanted)"
    elif [[ "$current" == "$wanted" ]]; then
        info "$bridge already has $wanted"
    else
        warn "$bridge has $current, but the config now says $wanted."
        warn "Use the matching HOST_NUMBER (-i) or change $bridge in /etc/network/interfaces."
    fi
}
check_bridge vmbr0 "192.168.123.$IP_PART/24"
check_bridge vmbr1 "192.168.223.$IP_PART/24"

if [[ -z "$STANDALONE" ]]; then
    info "Clustered host: bridging $DEVICE_NAME into vmbr0"
    set_toml_value "$CFG_FOLDER/vm.toml" bridge_gw_daas      "192.168.123.1"
    set_toml_value "$CFG_FOLDER/vm.toml" bridge_adapter_daas "$DEVICE_NAME"
else
    info "Standalone host: no uplink on vmbr0"
    set_toml_value "$CFG_FOLDER/vm.toml" bridge_gw_daas      ""
    set_toml_value "$CFG_FOLDER/vm.toml" bridge_adapter_daas ""
    if ip link show "$DEVICE_NAME" >/dev/null 2>&1; then
        run dhclient "$DEVICE_NAME"
    else
        warn "Device $DEVICE_NAME not found, skipping dhclient (use -n to set it)"
    fi
fi

# ============================================================
step "nginx"
# ============================================================

"$DAAS_INSTALLER_DIR/daas/mkcert.bash" -o "$HOST_NAME" -c "$FQDN"

run cp "$DAAS_INSTALLER_DIR/daas/nginx.conf" /etc/nginx/nginx.conf
sed -e "s#pve1.cluster.local#$FQDN#g" "$DAAS_INSTALLER_DIR/daas/daas.conf" \
    | write_file "$NGINX_SITE"
run ln -sfn "$NGINX_SITE" "$NGINX_ENABLED"

run nginx -t
enable_and_restart nginx

# ============================================================
step "Runtime data (src/data)"
# ============================================================

# -n: never overwrite data that already exists from an earlier run
mkdir -p "$REPO_FOLDER/src/data"
run cp -rn "$REPO_FOLDER/src/data_template/." "$REPO_FOLDER/src/data/"

success "Backend configured for $FQDN"
