#!/usr/bin/env bash
#
# Creates a Proxmox cluster (-c) or joins an existing one (-i).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

usage() {
    cat <<EOF >&2
Usage: $0 (-c <cluster-name> | -i <cluster-ip>) -l <link-ip>

Options:
    -c    Create a new cluster with this name
    -i    Join the cluster that runs on this IP
    -l    IP of this node on the cluster link (link0)
EOF
    exit 1
}

CLUSTER_NAME=""
CLUSTER_IP=""
LINK_IP=""
ACTION=""
while getopts ":c:i:l:" o; do
    case "$o" in
        c) CLUSTER_NAME="$OPTARG"; ACTION="create" ;;
        i) CLUSTER_IP="$OPTARG"; ACTION="join" ;;
        l) LINK_IP="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$ACTION" ]] || usage
[[ -n "$LINK_IP" ]] || die "Missing -l <link-ip> (set LINK_IP=... for make)"
require_root
require_cmds pvecm

case "$ACTION" in
    create)
        step "Create cluster '$CLUSTER_NAME' (link0 $LINK_IP)"
        run pvecm create "$CLUSTER_NAME" --link0 "$LINK_IP"
        ;;
    join)
        step "Join cluster at $CLUSTER_IP (link0 $LINK_IP)"
        # Not through `run`: pvecm add asks for the root password of the
        # cluster node and confirms its SSH fingerprint, so it needs the
        # terminal directly.
        info "\$ pvecm add $CLUSTER_IP --link0 $LINK_IP (interactive)"
        pvecm add "$CLUSTER_IP" --link0 "$LINK_IP"
        ;;
esac

run pvecm status
success "Cluster $ACTION done"
