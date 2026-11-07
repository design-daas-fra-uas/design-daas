#!/usr/bin/env bash
#
# Copies ISO files into a Proxmox ISO storage (default: daas-iso).
# Replaces the old `python3 -m backend.noweb.cmdline prox-upload-iso`, which
# no longer exists. The storage is created by the backend on its first start.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

usage() {
    echo "Usage: $0 [-s <storage>] <iso-file>..." >&2
    exit 1
}

STORAGE="daas-iso"
while getopts ":s:" o; do
    case "$o" in
        s) STORAGE="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

(( $# > 0 )) || usage
require_root
require_cmds pvesm

if ! pvesm status --storage "$STORAGE" >/dev/null 2>&1; then
    die "Storage '$STORAGE' not found. Start the backend once (make daas-start) so it creates it."
fi

for iso in "$@"; do
    if [[ ! -f "$iso" ]]; then
        warn "Skipping missing ISO: $iso"
        continue
    fi
    name="$(basename "$iso")"
    target="$(pvesm path "$STORAGE:iso/$name")"
    info "Uploading $iso -> $target ($(du -h "$iso" | cut -f1))"
    mkdir -p "$(dirname "$target")"
    run cp "$iso" "$target"
    success "Uploaded $name"
done
