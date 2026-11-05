#!/usr/bin/env bash
#
# Installs every host dependency of the Design DaaS stack in one place, so
# the later steps only check for them (require_cmds) and never apt-get:
#   - packages: docker, nginx, dnsmasq, Python build tools, ISO tools, ...
#   - docker: data root in /home/daas-docker
#   - docker-compose (pinned release binary, used by Java backend + frontend)
#   - an SSH key for root (/root/.ssh/id_rsa): the desktop images, the
#     extensions container and the ISOs authorize it
#
# Safe to run again: installed packages are kept, nothing is upgraded.
# Run it after proxmox-install (PVE kernel booted), see installer/README.md.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

DOCKER_DATA_ROOT="/home/daas-docker"
COMPOSE_VERSION="v2.24.0"
COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"
COMPOSE_BIN="/usr/bin/docker-compose"
SSH_KEY="/root/.ssh/id_rsa"

# What each group is needed for
PKG_BASE=(ca-certificates curl wget git jq openssl rsync parallel openssh-client isc-dhcp-client)
PKG_PYTHON=(python3-pip python3.11-venv python3.11-dev python3-click build-essential)
PKG_HOST=(docker.io nginx dnsmasq)
PKG_ISO=(syslinux syslinux-utils isolinux xorriso genisoimage unzip unrar-free)

usage() {
    cat <<EOF >&2
Usage: $0

Installs the host packages, docker-compose and root's SSH key.
EOF
    exit 1
}

(( $# == 0 )) || usage
require_root

# ============================================================
step "Packages"
# ============================================================

run apt-get update
info "Base:   ${PKG_BASE[*]}"
info "Python: ${PKG_PYTHON[*]}"
info "Host:   ${PKG_HOST[*]}"
info "ISO:    ${PKG_ISO[*]}"
apt_install "${PKG_BASE[@]}" "${PKG_PYTHON[@]}" "${PKG_HOST[@]}" "${PKG_ISO[@]}"
run pip install docker --break-system-packages

# ============================================================
step "docker (data root: $DOCKER_DATA_ROOT)"
# ============================================================

mkdir -p "$DOCKER_DATA_ROOT"
write_file /etc/docker/daemon.json <<EOF
{
    "data-root": "$DOCKER_DATA_ROOT"
}
EOF
enable_and_restart docker

# ============================================================
step "docker-compose $COMPOSE_VERSION"
# ============================================================

if [[ -x "$COMPOSE_BIN" ]] && "$COMPOSE_BIN" version 2>/dev/null | grep -q "${COMPOSE_VERSION}"; then
    info "docker-compose ${COMPOSE_VERSION} already installed"
else
    run curl -fSL "$COMPOSE_URL" -o "$COMPOSE_BIN"
    chmod +x "$COMPOSE_BIN"
    success "Installed $("$COMPOSE_BIN" version)"
fi

# ============================================================
step "SSH key for root ($SSH_KEY)"
# ============================================================

if [[ -f "$SSH_KEY" && -f "$SSH_KEY.pub" ]]; then
    info "Already present"
    # ssh ignores a private key that others can read
    if [[ "$(stat -c %a "$SSH_KEY")" != 600 ]]; then
        warn "$SSH_KEY had mode $(stat -c %a "$SSH_KEY"), setting 600"
        chmod 600 "$SSH_KEY"
    fi
else
    mkdir -p -m 700 /root/.ssh
    run ssh-keygen -q -t rsa -b 4096 -N '' -C "root@$(hostname -s) (design-daas)" -f "$SSH_KEY"
    success "Created $SSH_KEY"
fi

success "Dependencies installed"
