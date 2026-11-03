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
Usage: $0 -i <ip-address> -h <hostname> -d <domain>

Options:
    -i    IP address of this host
    -h    Host name (e.g. pve1)
    -d    Domain (e.g. daas-design.de)
EOF
    exit 1
}

PROXMOX_IP=""
PROXMOX_HOST=""
PROXMOX_DOMAIN=""
while getopts ":i:h:d:" o; do
    case "$o" in
        i) PROXMOX_IP="$OPTARG" ;;
        h) PROXMOX_HOST="$OPTARG" ;;
        d) PROXMOX_DOMAIN="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$PROXMOX_IP" && -n "$PROXMOX_HOST" && -n "$PROXMOX_DOMAIN" ]] || usage
require_root

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
    run apt-get remove -y linux-image-amd64 'linux-image-6.1*' os-prober \
        || warn "Debian kernel / os-prober already removed"
    apt_install pip docker.io nginx build-essential python3.11-dev
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
    # TODO: the router option points at the host's main IP, not at the vmbr1
    # bridge address (192.168.223.x). Check this is intended.
    write_file /etc/dnsmasq.conf <<EOF
server=8.8.8.8
interface=vmbr1
dhcp-range=192.168.223.50,192.168.223.75,1m
dhcp-option=vmbr1,3,$PROXMOX_IP
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
