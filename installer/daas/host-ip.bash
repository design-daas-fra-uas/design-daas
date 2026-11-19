#!/usr/bin/env bash
#
# Prints the host's main IPv4 address, the HOST_IP of the installer.
# HOST_IP empty: the source address of the default route (the address the
# host reaches the internet and the LAN with). HOST_IP set: it is checked to be
# an address of this host, so a value copied from another machine or left from
# an example stops the install before /etc/hosts gets a wrong address.
# Changes nothing.
#
# Usage: ./host-ip.bash [<HOST_IP>]

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

ip_wanted="${1:-}"
own_ips="$(ip -4 -o addr show scope global | awk '{sub(/\/.*/, "", $4); print $4}')"

if [[ -z "$ip_wanted" ]]; then
    ip_wanted="$(ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit }}')"
    [[ -n "$ip_wanted" ]] || die "HOST_IP is empty and no default route was found to detect it: connect the host to the network, or set HOST_IP in daas.env (see: ip -br -4 addr)"
fi

[[ "$ip_wanted" =~ ^[0-9]+(\.[0-9]+){3}$ ]] \
    || die "HOST_IP '$ip_wanted' is not an IPv4 address: leave it empty in daas.env to detect it"
grep -qxF "$ip_wanted" <<<"$own_ips" \
    || die "HOST_IP $ip_wanted is not an address of this host (it has: $(echo $own_ips)): leave it empty in daas.env to detect it, or set the right one"

echo "$ip_wanted"
