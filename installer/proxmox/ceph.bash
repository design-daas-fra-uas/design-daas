#!/usr/bin/env bash
#
# Ceph setup on Proxmox. One action per call:
#   ceph    install Ceph (quincy), init the network, create mon + mgr
#   osd     create an OSD on a disk
#   cephfs  create the MDS (+ standby) and the CephFS "daasfs"
#   pool    create the RBD pool "daas-ceph" and add it as storage

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

POOL_NAME="daas-ceph"
FS_DAASNAME="daasfs"

usage() {
    cat <<EOF >&2
Usage: $0 -a <ceph|osd|cephfs|pool> [-n <ceph-cidr>] [-d <disk>]

Options:
    -a    Action
    -n    Ceph network CIDR (required for 'ceph')
    -d    Disk for the OSD (default: /dev/vdb)
EOF
    exit 1
}

ACTION=""
CEPH_NETWORK=""
CEPH_DISK="/dev/vdb"
while getopts ":a:n:d:" o; do
    case "$o" in
        a) ACTION="$OPTARG" ;;
        d) CEPH_DISK="$OPTARG" ;;
        n) CEPH_NETWORK="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$ACTION" ]] || usage
require_root
require_cmds pveceph

action_ceph() {
    [[ -n "$CEPH_NETWORK" ]] || die "Action 'ceph' needs -n <ceph-cidr>"
    step "Install Ceph (network $CEPH_NETWORK)"
    # pveceph asks for confirmation ("yJ" answers both English and German prompts)
    echo "yJ" | run pveceph install -repository no-subscription -version quincy
    run pveceph init --network "$CEPH_NETWORK"
    run pveceph mon create
    run pveceph mgr create
}

action_osd() {
    step "Create OSD on $CEPH_DISK"
    [[ -b "$CEPH_DISK" ]] || die "Not a block device: $CEPH_DISK"
    run pveceph osd create "$CEPH_DISK"
}

action_cephfs() {
    step "Create CephFS $FS_DAASNAME"
    run pveceph mds create --name "$FS_DAASNAME"
    run pveceph mds create --name "${FS_DAASNAME}-standby"
    run pveceph fs create -name "$FS_DAASNAME" -add-storage 0 -pg_num 16
}

action_pool() {
    step "Create pool $POOL_NAME"
    run pveceph pool create "$POOL_NAME" -pg_num 8 --add_storages
}

case "$ACTION" in
    ceph)   action_ceph ;;
    osd)    action_osd ;;
    cephfs) action_cephfs ;;
    pool)   action_pool ;;
    *)      error "Unknown action: $ACTION"; usage ;;
esac

success "Ceph action '$ACTION' done"
