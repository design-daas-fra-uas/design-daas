#!/usr/bin/env bash
#
# Installs Proxmox VE on Debian 12 in two runs:
#   1st run (Debian kernel): add the PVE repo, install the PVE kernel and set
#                            the hostname. Then reboot.
#   2nd run (PVE kernel):    install proxmox-ve, docker, nginx and dnsmasq.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

PROXMOX_DEBURL="http://download.proxmox.com/debian/pve"
PROXMOX_KEYURL="https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg"
DOCKER_DATA_ROOT="/home/daas-docker"

usage() {
    cat <<EOF >&2
Usage: $0 -i <ip-address> -h <hostname> -d <domain> [-n <ip-part>]

Options:
    -i    IP address of this host
    -h    Host name (e.g. pve1)
    -d    Domain (e.g. daas-design.de)
    -n    Last octet of this host on the DaaS networks (default: 1); the
          instances on vmbr1 use 192.168.223.<ip-part> as their gateway
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

# vmbr1 address of this host (same value daas/configure.bash writes to
# bridge_cidr_inst). The backend masquerades instance traffic, so this is
# the instances' default gateway.
INST_GATEWAY="192.168.223.$IP_PART"

install_kernel() {
    step "Proxmox repository + PVE kernel"
    run apt-get update
    apt_install wget python3.11-venv

    write_file /etc/apt/sources.list.d/pve-install-repo.list <<EOF
deb [arch=amd64] $PROXMOX_DEBURL bookworm pve-no-subscription
EOF
    run wget -q "$PROXMOX_KEYURL" -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

    run apt-get update
    run apt-get full-upgrade -y
    apt_install pve-kernel-6.2
    if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
        info "Removing enterprise repository (needs a subscription)"
        rm -f /etc/apt/sources.list.d/pve-enterprise.list
    fi
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
    step "Proxmox VE + docker + build tools"
    apt_install proxmox-ve open-iscsi
    # Removed one by one: apt aborts the whole call if one name is unknown
    local pkg
    for pkg in linux-image-amd64 'linux-image-6.1*' os-prober; do
        run apt-get remove -y "$pkg" || info "Not installed: $pkg"
    done
    apt_install python3-pip docker.io nginx build-essential python3.11-dev
    run pip install docker --break-system-packages
    run update-grub

    info "Docker data root: $DOCKER_DATA_ROOT"
    mkdir -p "$DOCKER_DATA_ROOT"
    write_file /etc/docker/daemon.json <<EOF
{
    "data-root": "$DOCKER_DATA_ROOT"
}
EOF
    enable_and_restart docker
}

install_dnsmasq() {
    step "dnsmasq (DHCP for instances on vmbr1)"
    apt_install python3-click dnsmasq
    info "Instance gateway (vmbr1): $INST_GATEWAY"
    write_file /etc/dnsmasq.conf <<EOF
server=8.8.8.8
interface=vmbr1
dhcp-range=192.168.223.50,192.168.223.75,1m
dhcp-option=vmbr1,3,$INST_GATEWAY
dhcp-option=vmbr1,6,8.8.8.8
dhcp-leasefile=/var/lib/misc/dnsmasq.leases
conf-dir=/etc/dnsmasq.d,.bak
EOF
    write_file /etc/dnsmasq.d/pve-hosts.conf <<EOF
dhcp-host=de:ad:be:ef:00:64,id:vm100,192.168.223.100,1m
dhcp-host=de:ad:be:ef:00:65,id:vm100,192.168.223.101,1m
dhcp-host=de:ad:be:ef:00:66,id:vm100,192.168.223.102,1m
dhcp-host=de:ad:be:ef:00:67,id:vm100,192.168.223.103,1m
dhcp-host=de:ad:be:ef:00:68,id:vm100,192.168.223.104,1m
EOF
    # vmbr1 is created by the backend on its first start, so dnsmasq may
    # not be able to start yet.
    if run systemctl restart dnsmasq.service && systemctl is-active --quiet dnsmasq; then
        success "dnsmasq running"
    else
        warn "dnsmasq is not running yet (vmbr1 is created when the backend starts)"
    fi
}

KERNEL="$(uname -r)"
info "Running kernel: $KERNEL"

if [[ "$KERNEL" != *pve* ]]; then
    info "Phase 1 of 2: no PVE kernel yet"
    install_kernel
    configure_hostname
    success "Phase 1 done. Reboot into the PVE kernel, then run this again."
else
    info "Phase 2 of 2: PVE kernel detected"
    install_pve
    install_dnsmasq
    success "Proxmox VE installed"
fi
