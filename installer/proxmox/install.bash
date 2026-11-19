#!/usr/bin/env bash
#
# Installs Proxmox VE on Debian 12 in two runs:
#   1st run (Debian kernel): add the PVE repo, install the PVE kernel and set
#                            the hostname. Then reboot.
#   2nd run (PVE kernel):    install proxmox-ve and drop the Debian kernel.
#
# Everything else the stack needs (docker, nginx, dnsmasq, ...) is installed
# by deps/install.bash (make deps); dnsmasq is configured by daas-configure.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

PROXMOX_DEBURL="http://download.proxmox.com/debian/pve"
PROXMOX_KEYURL="https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg"

usage() {
    cat <<EOF >&2
Usage: $0 -i <ip-address> -h <hostname> -d <domain> [-n <ip-part>]

Options:
    -i    IP address of this host
    -h    Host name (e.g. pve1)
    -d    Domain (e.g. daas-design.de)
    -n    Last octet of this host on the DaaS networks (default: 1)
EOF
    exit 1
}

PROXMOX_IP=""
PROXMOX_HOST=""
PROXMOX_DOMAIN=""
IP_PART=1
while getopts ":i:h:d:n:" o; do
    case "$o" in
        i) PROXMOX_IP="$OPTARG" ;;
        h) PROXMOX_HOST="$OPTARG" ;;
        d) PROXMOX_DOMAIN="$OPTARG" ;;
        n) IP_PART="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$PROXMOX_IP" && -n "$PROXMOX_HOST" && -n "$PROXMOX_DOMAIN" ]] || usage
[[ "$IP_PART" =~ ^[0-9]+$ ]] && (( IP_PART >= 1 && IP_PART <= 254 )) \
    || die "Invalid IP part '$IP_PART' (expected 1-254)"
require_root

install_kernel() {
    step "Proxmox repository + PVE kernel"
    run apt-get update
    apt_install wget

    write_file /etc/apt/sources.list.d/pve-install-repo.list <<EOF
deb [arch=amd64] $PROXMOX_DEBURL bookworm pve-no-subscription
EOF
    run wget -q "$PROXMOX_KEYURL" -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

    run apt-get update
    run apt-get full-upgrade -y
    # The kernel series Proxmox currently supports (and its updates)
    apt_install proxmox-default-kernel
    disable_enterprise_repos
}

configure_hostname() {
    step "Hostname: $PROXMOX_HOST.$PROXMOX_DOMAIN ($PROXMOX_IP)"
    [[ -f /etc/hosts.bak ]] || cp /etc/hosts /etc/hosts.bak
    [[ -f /etc/hostname.bak ]] || cp /etc/hostname /etc/hostname.bak
    run hostname -b "$PROXMOX_HOST"
    echo "$PROXMOX_HOST" | write_file /etc/hostname
    write_file /etc/hosts <<EOF
127.0.0.1 localhost
$PROXMOX_IP $PROXMOX_HOST.$PROXMOX_DOMAIN $PROXMOX_HOST

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
}

install_pve() {
    step "Proxmox VE"
    apt_install proxmox-ve open-iscsi
    # Removed one by one: apt aborts the whole call if one name is unknown
    local pkg
    for pkg in linux-image-amd64 'linux-image-6.1*' os-prober; do
        run apt-get remove -y "$pkg" || info "Not installed: $pkg"
    done
    run update-grub
    disable_enterprise_repos
}

# Keeps the host online after Proxmox takes over the network: proxmox-ve
# replaces ifupdown with ifupdown2, and Proxmox rewrites
# /etc/network/interfaces with every physical device as "manual". A wired
# connection survives that. A Wi-Fi connection only survives if
# NetworkManager runs it and still manages devices listed in that file
# (Debian's default managed=false makes it drop them after the next boot).
keep_network() {
    step "Network connection"
    local dev nm_conf=/etc/NetworkManager/conf.d/90-daas-ifupdown.conf
    dev="$(ip route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}')"
    if [[ -z "$dev" ]]; then
        warn "No default route: the installer needs internet access"
        return 0
    fi
    if [[ ! -d "/sys/class/net/$dev/wireless" ]]; then
        info "Online over $dev (wired): nothing to do"
        return 0
    fi
    if systemctl is-active --quiet NetworkManager \
            && nmcli -t -f DEVICE,STATE device 2>/dev/null | grep -q "^$dev:connected"; then
        write_file "$nm_conf" <<EOF
# Written by the Design DaaS installer (proxmox/install.bash): keep managing
# devices that Proxmox lists in /etc/network/interfaces, e.g. the Wi-Fi $dev
[ifupdown]
managed=true
EOF
        info "Online over Wi-Fi $dev, run by NetworkManager: it keeps it after the reboot"
        return 0
    fi
    error "The host is online over Wi-Fi ($dev), but NetworkManager does not run it."
    error "Proxmox replaces ifupdown and rewrites /etc/network/interfaces, so this"
    error "Wi-Fi would be gone after the reboot. Use a wired connection, or let"
    error "NetworkManager run the Wi-Fi first (README.md, step 1), then run this again."
    die "Wi-Fi without NetworkManager"
}

KERNEL="$(uname -r)"
info "Running kernel: $KERNEL"

keep_network
if [[ "$KERNEL" != *pve* ]]; then
    info "Phase 1 of 2: no PVE kernel yet"
    install_kernel
    configure_hostname
    success "Phase 1 done. Reboot into the PVE kernel, then run this again."
else
    info "Phase 2 of 2: PVE kernel detected"
    install_pve
    success "Proxmox VE installed. Next: make deps"
fi
