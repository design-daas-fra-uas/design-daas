#!/usr/bin/env bash
#
# Proxmox configuration step. There is nothing to do here at the moment:
# the backend creates the Proxmox storages (daas-iso, daas-img) and network
# bridges (vmbr0, vmbr1, vmbr8, vmbr9) itself on every start
# (ApiProxmox.configure_services in src/app/daas/vm/proxmox/).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

usage() { echo "Usage: $0 -r <repo-folder> -h <hostname> [-d <domain>] [-i <ip-part>]" >&2; exit 1; }

REPO_FOLDER=""
HOST_NAME=""
while getopts ":r:h:i:d:" o; do
    case "$o" in
        r) REPO_FOLDER="$OPTARG" ;;
        h) HOST_NAME="$OPTARG" ;;
        d|i) ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ -n "$REPO_FOLDER" && -n "$HOST_NAME" ]] || usage
require_dir "$REPO_FOLDER"

info "Nothing to configure: storages and bridges are created by the backend on start"
