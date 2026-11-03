#!/bin/bash

set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this installer as root."
    exit 1
fi

# Usage
usage() {
    echo "Usage: $0 [-i <ip-address>] [-h <hostname>] [-d <domain>]" 1>&2
    exit 1
}

# Default params (devenv)
PROXMOX_IP=
PROXMOX_HOST=
PROXMOX_DOMAIN=
PROXMOX_DEBURL=http://download.proxmox.com/debian/pve
PROXMOX_KEYURL=https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg

export DEBIAN_FRONTEND=noninteractive

# Must run as root
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root"
    exit 1
fi

# Read options
while getopts ":i:h:d:" o; do
    case "$o" in
        i) PROXMOX_IP=${OPTARG} ;;
        h) PROXMOX_HOST=${OPTARG} ;;
        d) PROXMOX_DOMAIN=${OPTARG} ;;
        *) usage ;;
    esac
done
shift $((OPTIND-1))

# Bail if requirements are not met
if  [ "$PROXMOX_IP" = "" ] || [ "$PROXMOX_HOST" = "" ] || [ "$PROXMOX_DOMAIN" = "" ] ; then
    usage
fi

# Check Debian version
if ! grep -q 'VERSION_CODENAME=trixie' /etc/os-release; then
    echo "ERROR: This installer currently targets Debian 13 (Trixie)."
    exit 1
fi

install_kernel() {
    echo "=== Installing Proxmox VE 9 repository ==="
    
    apt update
    apt install -y wget python3 python3-venv python3-pip
    
    # Sources
    wget "$PROXMOX_KEYURL" \
        -O /usr/share/keyrings/proxmox-archive-keyring.gpg
        
    # Configure Proxmox VE 9 repository (Debian Trixie)
    cat > /etc/apt/sources.list.d/proxmox.sources <<EOF
Types: deb
URIs: $PROXMOX_DEBURL
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

    # Remove previous Bookworm repository configuration
    rm -f /etc/apt/sources.list.d/pve-install-repo.list
    
    echo "=== Updating system ==="
    
    apt update
    apt full-upgrade -y
    
    echo "=== Installing Proxmox kernel ==="
    apt install -y proxmox-default-kernel
    
    echo
    echo "Proxmox kernel installed."
    echo "Please reboot and run this installer again."
}

install_pve() {
    echo "=== Installing Proxmox VE 9 ==="
    
    apt install -y \
        proxmox-ve \
        postfix \
        open-iscsi \
        chrony
    
    echo "=== Installing additional packages ==="
    
    apt install -y \
        nginx \
        docker.io \
        build-essential \
        python3 \
        python3-dev \
        python3-venv \
        python3-pip \
        python3-click \
        python3-docker \
        dnsmasq
    
    # Remove Debian kernel after confirming PVE kernel is running
    apt remove -y linux-image-amd64
    apt remove -y os-prober
    
    update-grub

    # Prepare Docker daemon
    mkdir -p /etc/docker
    mkdir -p /home/daas-docker
    
    cat > /etc/docker/daemon.json <<EOF
{
    "data-root": "/home/daas-docker"
}
EOF
        
    systemctl enable docker
    systemctl restart docker
    
    echo "=== Proxmox VE installation completed ==="
}

install_dnsmasq(){
    echo "=== Configuring dnsmasq ==="
    
    cat > /etc/dnsmasq.conf <<EOF 
server=8.8.8.8
interface=vmbr1
dhcp-range=192.168.223.50,192.168.223.75,1m
dhcp-option=vmbr1,3,$PROXMOX_IP
dhcp-option=vmbr1,6,8.8.8.8
dhcp-leasefile=/var/lib/misc/dnsmasq.leases
conf-dir=/etc/dnsmasq.d,.bak
EOF

    mkdir -p /etc/dnsmasq.d
    
    cat > /etc/dnsmasq.d/pve-hosts.conf <<EOF 
dhcp-host=de:ad:be:ef:00:64,id:vm100,192.168.223.100,1m
dhcp-host=de:ad:be:ef:00:65,id:vm100,192.168.223.101,1m
dhcp-host=de:ad:be:ef:00:66,id:vm100,192.168.223.102,1m
dhcp-host=de:ad:be:ef:00:67,id:vm100,192.168.223.103,1m
dhcp-host=de:ad:be:ef:00:68,id:vm100,192.168.223.104,1m
EOF
    systemctl enable dnsmasq
    systemctl restart dnsmasq
}

configure_hostname() {
    echo "=== Configuring hostname ==="
    
    cp /etc/hosts /etc/hosts.bak
    cp /etc/hostname /etc/hostname.bak
    
    hostname -b "$PROXMOX_HOST"
    
    printf '%s\n' "$PROXMOX_HOST" | tee /etc/hostname >/dev/null
    
    cat > /etc/hosts <<EOF 
127.0.0.1 localhost
$PROXMOX_IP $PROXMOX_HOST.$PROXMOX_DOMAIN $PROXMOX_HOST

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
}

# Main installation flow
KERNEL=$(uname -r)

if [[ "$KERNEL" != *-pve ]]; then
    echo "Running Debian kernel: $KERNEL"

    configure_hostname
    install_kernel

else
    echo "Running Proxmox kernel: $KERNEL"

    install_pve
    install_dnsmasq

    echo
    echo "======================================"
    echo " Proxmox VE 9 installation completed"
    echo "======================================"
    echo "Hostname: $PROXMOX_HOST"
    echo "IP:       $PROXMOX_IP"
    echo "URL:      https://$PROXMOX_IP:8006"
fi
