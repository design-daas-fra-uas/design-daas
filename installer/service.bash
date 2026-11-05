#!/usr/bin/env bash
#
# Controls every part of the Design DaaS installation:
#
#   service.bash [-e <env-file>] <action> [-p] <component>...
#
# Components, by kind:
#   service    java (java-backend.service: Java backend + its MariaDB)
#              daas (daas.service), frontend (frontend.service)
#   container  guacd, rabbit, db, extensions: images built from installer/
#              (guacd, rabbit, mariadb, extensions); the DaaS backend starts
#              them on its start (src/config/container.toml) and stops them
#              on its stop. Here they can also be controlled one by one.
#   image      x11vnc, wine: desktop images, the DaaS backend starts one
#              container per instance from them
#   host       nginx, dnsmasq, docker, proxmox (the pve*.service units):
#              installed by proxmox-install / daas-install, cannot be deleted
#   iso        the generated ISOs (iso/iso/*-daas.iso)
#
# Groups: services, containers, images, host, all. "all" means the three
# services for start/stop/restart/logs (daas starts the containers), every
# component for status, and services + containers + images for delete.
#
# Actions:
#   start | stop | restart   service, container, host
#   status                   one line per component
#   logs                     follow the logs (containers: one at a time)
#   delete [-p]              remove it; -p also deletes its data
#                            (java: DB + keys, daas: src/data + nginx site,
#                            frontend: nginx site, db: src/data/db/mariadb)
#
# Installing is done by the Makefile (<component>-install / -reinstall).

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.bash"

REPO_FOLDER="$(cd "$DAAS_INSTALLER_DIR/.." && pwd)"

# Start order: the DaaS backend logs in through the Java backend
SERVICES=(java daas frontend)
CONTAINERS=(guacd rabbit db extensions)
IMAGES=(x11vnc wine)
HOST=(nginx dnsmasq docker proxmox)
PVE_UNITS=(pve-cluster pvedaemon pveproxy pvestatd pvescheduler pve-firewall
           pvefw-logger pve-ha-crm pve-ha-lrm pve-lxc-syscalld spiceproxy)
ISO_TYPES=(win10 win11 debian12)
ISO_DIR="$DAAS_INSTALLER_DIR/iso/iso"

usage() {
    cat <<EOF >&2
Usage: $0 [-e <env-file>] <action> [-p] <component>...

Actions:    start stop restart status logs delete
Components: ${SERVICES[*]} ${CONTAINERS[*]} ${IMAGES[*]} ${HOST[*]} iso
Groups:     services containers images host all
Options:
    -e    Stack env file (installer/daas.env), for JAVA_PORT
    -p    With delete: also delete the data
EOF
    exit 1
}

contains() {
    local x="$1"
    shift
    [[ " $* " == *" $x "* ]]
}

# kind_of COMPONENT: service | container | image | host | iso
kind_of() {
    if contains "$1" "${SERVICES[@]}"; then echo service
    elif contains "$1" "${CONTAINERS[@]}"; then echo container
    elif contains "$1" "${IMAGES[@]}"; then echo image
    elif contains "$1" "${HOST[@]}"; then echo host
    elif [[ "$1" == iso ]]; then echo iso
    else die "Unknown component '$1' (see $0 without arguments)"
    fi
}

# unit_of SERVICE: systemd unit name (without .service)
unit_of() {
    case "$1" in
        java) echo java-backend ;;
        *)    echo "$1" ;;
    esac
}

# Service containers: container name and image as in container.toml
container_of() {
    case "$1" in
        db) echo daas-0-db ;;
        *)  echo "daas-0-$1" ;;
    esac
}
image_of() {
    case "$1" in
        db)     echo daas-0-mariadb ;;
        x11vnc) echo x11vnc ;;
        wine)   echo wine ;;
        *)      echo "daas-0-$1" ;;
    esac
}

# image_alias_of IMAGE: second tag of a desktop image (TAGS in its Makefile)
image_alias_of() {
    case "$1" in
        x11vnc) echo daas.contx11 ;;
        wine)   echo daas.contwine ;;
    esac
}

# host_units HOST: the systemd units of a host component
host_units() {
    if [[ "$1" == proxmox ]]; then
        printf '%s.service\n' "${PVE_UNITS[@]}"
    else
        echo "$1.service"
    fi
}

container_running() {
    [[ -n "$(docker ps -q --filter "name=^$(container_of "$1")$" 2>/dev/null)" ]]
}

image_present() {
    docker image inspect "$(image_of "$1")" >/dev/null 2>&1
}

# ============================================================
# Actions per kind
# ============================================================

do_start() {
    local c="$1" action="$2" unit name
    case "$(kind_of "$c")" in
        service)
            unit="$(unit_of "$c").service"
            [[ -f "/etc/systemd/system/$unit" ]] || die "$unit is not installed (make $c-install)"
            run systemctl "$action" "$unit"
            sleep 2
            check_active "$unit"
            if [[ "$c" == java ]]; then
                wait_http "http://127.0.0.1:${JAVA_PORT:-8080}/oauth2/user/token" \
                    || die "Java backend did not answer after 5 min (make java-logs)"
            fi
            ;;
        container)
            name="$(container_of "$c")"
            image_present "$c" || die "Image $(image_of "$c") is missing (make $c-install)"
            if container_running "$c"; then
                if [[ "$action" == start ]]; then
                    info "$name is already running"
                    return 0
                fi
                run docker kill "$name"
            fi
            local args=()
            mapfile -t args < <(python3 -I "$DAAS_INSTALLER_DIR/lib/service_container.py" "$REPO_FOLDER" "$name")
            (( ${#args[@]} > 0 )) || die "Could not read the settings of $name"
            run docker run "${args[@]}" >/dev/null
            sleep 1
            container_running "$c" || { docker logs --tail 30 "$name" 2>&1 || true; die "$name did not start"; }
            success "Container running: $name"
            ;;
        host)
            mapfile -t units < <(host_units "$c")
            run systemctl "$action" "${units[@]}"
            for unit in "${units[@]}"; do
                check_active "$unit"
            done
            ;;
        image)
            die "$c is a desktop image: the DaaS backend starts a container from it per instance"
            ;;
        iso)
            die "iso has nothing to start"
            ;;
    esac
}

do_stop() {
    local c="$1" name
    case "$(kind_of "$c")" in
        service)
            run systemctl stop "$(unit_of "$c").service"
            ;;
        container)
            name="$(container_of "$c")"
            if container_running "$c"; then
                # The backend kills them too; they run with --rm
                run docker kill "$name"
            else
                info "$name is not running"
            fi
            ;;
        host)
            [[ "$c" != proxmox ]] || warn "Stopping Proxmox: the web UI and the API go down"
            mapfile -t units < <(host_units "$c")
            run systemctl stop "${units[@]}"
            ;;
        *)
            die "$c has nothing to stop"
            ;;
    esac
    success "Stopped $c"
}

do_status() {
    local c="$1" kind state detail unit n total
    kind="$(kind_of "$c")"
    case "$kind" in
        service)
            unit="$(unit_of "$c").service"
            if [[ -f "/etc/systemd/system/$unit" ]]; then
                state="$(systemctl is-active "$unit" || true)"
                detail="$unit, $(systemctl is-enabled "$unit" || true)"
            else
                state="not installed"
                detail="make $c-install"
            fi
            ;;
        container)
            detail="$(container_of "$c") from $(image_of "$c")"
            if ! docker info >/dev/null 2>&1; then
                state="unknown"
                detail="docker not reachable (run as root)"
            elif container_running "$c"; then
                state="running"
            elif image_present "$c"; then
                state="stopped"
            else
                state="not installed"
            fi
            ;;
        image)
            detail="image $(image_of "$c")"
            if ! docker info >/dev/null 2>&1; then
                state="unknown"
                detail="docker not reachable (run as root)"
            elif image_present "$c"; then
                state="installed"
                detail+=", built $(docker image inspect -f '{{.Created}}' "$(image_of "$c")" | cut -c1-16)"
            else
                state="not installed"
            fi
            ;;
        host)
            mapfile -t units < <(host_units "$c")
            n=0
            for unit in "${units[@]}"; do
                if systemctl is-active --quiet "$unit"; then n=$((n + 1)); fi
            done
            total="${#units[@]}"
            if (( n == total )); then state="active"
            elif (( n == 0 )); then state="inactive"
            else state="partial"
            fi
            detail="$n/$total units active"
            ;;
        iso)
            n=0
            for t in "${ISO_TYPES[@]}"; do
                if [[ -f "$ISO_DIR/$t-daas.iso" ]]; then n=$((n + 1)); fi
            done
            state="not built"
            (( n == 0 )) || state="built"
            detail="$n/${#ISO_TYPES[@]} in iso/iso"
            ;;
    esac
    printf '%-11s %-10s %-14s %s\n' "$c" "$kind" "$state" "$detail"
}

do_delete() {
    local c="$1" name image
    case "$(kind_of "$c")" in
        service)
            "$DAAS_INSTALLER_DIR/$c/delete.bash" $PURGE
            ;;
        container|image)
            name="$(container_of "$c")"
            image="$(image_of "$c")"
            # Desktop images are built in a container of the same name
            if [[ "$(kind_of "$c")" == image ]]; then name="$image"; fi
            if [[ -n "$(docker ps -aq --filter "name=^${name}$")" ]]; then
                run docker rm -f "$name"
            fi
            if image_present "$c"; then
                # Desktop images also carry the tag their sample object runs
                run docker image rm -f "$image" $(image_alias_of "$c")
            else
                info "No image $image"
            fi
            if [[ "$c" == db && -n "$PURGE" ]]; then
                warn "Deleting the DaaS MariaDB data (src/data/db/mariadb)"
                run rm -rf "$REPO_FOLDER/src/data/db/mariadb"
            fi
            success "Deleted $c"
            ;;
        iso)
            # Only the generated ISOs; the downloaded source ISOs are kept
            for t in "${ISO_TYPES[@]}"; do
                rm -f "$ISO_DIR/$t-daas.iso"
            done
            success "Deleted the generated ISOs (the source ISOs in iso/iso are kept)"
            ;;
        host)
            die "$c is part of the host installation and is not deleted by the installer"
            ;;
    esac
}

# ============================================================
# Arguments
# ============================================================

ENV_FILE=""
while getopts ":e:" o; do
    case "$o" in
        e) ENV_FILE="$OPTARG" ;;
        :) die "Option -$OPTARG requires an argument." ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

(( $# >= 1 )) || usage
ACTION="$1"
shift
PURGE=""
if [[ "$ACTION" == delete && "${1:-}" == -p ]]; then
    PURGE="-p"
    shift
fi
(( $# >= 1 )) || usage

TARGETS=()
for arg in "$@"; do
    case "$arg" in
        services)   TARGETS+=("${SERVICES[@]}") ;;
        containers) TARGETS+=("${CONTAINERS[@]}") ;;
        images)     TARGETS+=("${IMAGES[@]}") ;;
        host)       TARGETS+=("${HOST[@]}") ;;
        all)
            case "$ACTION" in
                status) TARGETS+=("${HOST[@]}" "${SERVICES[@]}" "${CONTAINERS[@]}" "${IMAGES[@]}" iso) ;;
                delete) TARGETS+=("${SERVICES[@]}" "${CONTAINERS[@]}" "${IMAGES[@]}") ;;
                *)      TARGETS+=("${SERVICES[@]}") ;;
            esac
            ;;
        *)  kind_of "$arg" >/dev/null; TARGETS+=("$arg") ;;
    esac
done
# stop and delete go in reverse order
REVERSED=()
for (( i = ${#TARGETS[@]} - 1; i >= 0; i-- )); do
    REVERSED+=("${TARGETS[i]}")
done

if [[ -n "$ENV_FILE" ]]; then
    load_stack_env "$ENV_FILE" >/dev/null
fi

case "$ACTION" in
    start|restart)
        require_root
        for c in "${TARGETS[@]}"; do
            step "$ACTION $c"
            do_start "$c" "$ACTION"
        done
        ;;
    stop)
        require_root
        for c in "${REVERSED[@]}"; do
            step "stop $c"
            do_stop "$c"
        done
        ;;
    status)
        printf '%-11s %-10s %-14s %s\n' COMPONENT KIND STATE DETAIL
        for c in "${TARGETS[@]}"; do
            do_status "$c"
        done
        ;;
    logs)
        units=()
        containers=()
        for c in "${TARGETS[@]}"; do
            case "$(kind_of "$c")" in
                service)   units+=(-u "$(unit_of "$c").service") ;;
                host)      while read -r u; do units+=(-u "$u"); done < <(host_units "$c") ;;
                container) containers+=("$(container_of "$c")") ;;
                *)         die "$c has no logs" ;;
            esac
        done
        if (( ${#containers[@]} > 0 )); then
            (( ${#containers[@]} == 1 && ${#units[@]} == 0 )) \
                || die "Container logs one at a time (e.g. make db-logs)"
            exec docker logs -f --tail 100 "${containers[0]}"
        fi
        exec journalctl -f "${units[@]}"
        ;;
    delete)
        require_root
        for c in "${REVERSED[@]}"; do
            step "delete $c"
            do_delete "$c"
        done
        ;;
    *)
        usage
        ;;
esac
