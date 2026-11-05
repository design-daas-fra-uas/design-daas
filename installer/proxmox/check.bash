#!/usr/bin/env bash
#
# Checks the Proxmox host layer the DaaS stack runs on (see README.md):
# PVE kernel and services, the package sources (apt update must work for
# `make deps`), whether a newer kernel waits for a reboot, the storages and
# bridges the DaaS backend creates, and dnsmasq. Changes nothing (apt-get
# update only refreshes the package lists).
#
# Usage: ./check.bash [-e <env-file>]     (run as root)

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"
set +e

ENV_FILE=""
while getopts ":e:" o; do
    case "$o" in
        e) ENV_FILE="$OPTARG" ;;
        *) echo "Usage: $0 [-e <env-file>]" >&2; exit 1 ;;
    esac
done
require_root
HOST_NUMBER=""
[[ -z "$ENV_FILE" ]] || load_env_file "$ENV_FILE" >/dev/null

FAILED=0
ok()   { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }
note() { echo "  NOTE  $*"; }

echo "Checking the Proxmox host $(hostname)"

kernel="$(uname -r)"
if [[ "$kernel" == *pve* ]]; then ok "PVE kernel $kernel ($(pveversion | cut -d/ -f1-2))"; else fail "not a PVE kernel: $kernel (make proxmox-install, reboot)"; fi

newest="$(ls /boot/vmlinuz-*-pve 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -1)"
if [[ -n "$newest" && "$newest" != "$kernel" ]]; then
    note "kernel $newest is installed but not running: reboot to use it"
fi

for u in pve-cluster pvedaemon pveproxy pvestatd; do
    if systemctl is-active --quiet "$u"; then ok "$u"; else fail "$u not running"; fi
done

enabled="$(grep -lE '^deb .*enterprise\.proxmox\.com' /etc/apt/sources.list.d/*.list 2>/dev/null)"
if [[ -z "$enabled" ]]; then ok "no enterprise repository enabled"; else fail "enterprise repository enabled (needs a subscription): $enabled"; fi
if apt-get update -qq >/dev/null 2>&1; then ok "apt-get update works"; else fail "apt-get update fails: make deps would stop (apt-get update shows why)"; fi

# Created by the DaaS backend on its first start (src/config/vm.toml)
for s in daas-iso daas-img; do
    if pvesm status --storage "$s" >/dev/null 2>&1; then ok "storage $s"; else fail "storage $s missing (start the backend once: make daas-start)"; fi
done
for b in vmbr0 vmbr1; do
    adr="$(ip -4 -o addr show dev "$b" 2>/dev/null | awk '{print $4; exit}')"
    if [[ -z "$adr" ]]; then
        fail "bridge $b missing (created by the backend on its start)"
    elif [[ -n "$HOST_NUMBER" && "$adr" != *".$HOST_NUMBER/24" ]]; then
        fail "bridge $b has $adr, HOST_NUMBER is $HOST_NUMBER (make daas-configure, or fix /etc/network/interfaces)"
    else
        ok "bridge $b $adr"
    fi
done
if systemctl is-active --quiet dnsmasq; then ok "dnsmasq (DHCP on vmbr1)"; else fail "dnsmasq not running"; fi

if (( FAILED )); then
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: all checks passed"
