#!/usr/bin/env bash
#
# Controls the Design DaaS services after they are installed:
#
#   service.bash [-e <env-file>] <action> <service>...
#
# Services (systemd unit in brackets), "all" = all three in start order:
#   java      Java backend + its MariaDB  (java-backend.service)
#   daas      DaaS backend                (daas.service)
#   frontend  React frontend              (frontend.service)
#
# Actions:
#   start | stop | restart   systemctl, then check the unit runs
#   status                   one line per service
#   logs                     follow the journal of the services
#   delete [-p]              remove the service (<service>/delete.bash);
#                            -p also deletes its data, see each delete.bash
#
# Installing is done by <service>/install.bash (see the Makefile targets
# <service>-install and <service>-reinstall).

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.bash"

# Start order: the DaaS backend logs in through the Java backend
ALL_SERVICES=(java daas frontend)

usage() {
    cat <<EOF >&2
Usage: $0 [-e <env-file>] <action> [-p] <service>...

Actions:  start stop restart status logs delete
Services: ${ALL_SERVICES[*]} all
Options:
    -e    Stack env file (installer/daas.env), for JAVA_PORT
    -p    With delete: also delete the service's data
EOF
    exit 1
}

# unit_of SERVICE: systemd unit name (without .service)
unit_of() {
    case "$1" in
        java)     echo java-backend ;;
        daas)     echo daas ;;
        frontend) echo frontend ;;
        *)        die "Unknown service '$1' (expected: ${ALL_SERVICES[*]} all)" ;;
    esac
}

require_installed() {
    [[ -f "/etc/systemd/system/$1.service" ]] \
        || die "$1.service is not installed (make $2-install)"
}

# check_started SERVICE: the unit runs, and the Java backend answers HTTP
check_started() {
    local svc="$1" unit
    unit="$(unit_of "$svc")"
    sleep 2
    check_active "$unit.service"
    if [[ "$svc" == java ]]; then
        wait_http "http://127.0.0.1:${JAVA_PORT:-8080}/oauth2/user/token" \
            || die "Java backend did not answer after 5 min (make java-logs)"
    fi
}

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

SERVICES=()
for svc in "$@"; do
    if [[ "$svc" == all ]]; then
        SERVICES+=("${ALL_SERVICES[@]}")
    else
        unit_of "$svc" >/dev/null
        SERVICES+=("$svc")
    fi
done
# stop and delete go in reverse order
REVERSED=()
for (( i = ${#SERVICES[@]} - 1; i >= 0; i-- )); do
    REVERSED+=("${SERVICES[i]}")
done

if [[ -n "$ENV_FILE" ]]; then
    load_stack_env "$ENV_FILE" >/dev/null
fi

case "$ACTION" in
    start|restart)
        require_root
        for svc in "${SERVICES[@]}"; do
            unit="$(unit_of "$svc")"
            require_installed "$unit" "$svc"
            step "$ACTION $svc"
            run systemctl "$ACTION" "$unit.service"
            check_started "$svc"
        done
        ;;
    stop)
        require_root
        for svc in "${REVERSED[@]}"; do
            unit="$(unit_of "$svc")"
            step "stop $svc"
            run systemctl stop "$unit.service"
            success "Stopped $unit.service"
        done
        ;;
    status)
        printf '%-10s %-22s %-10s %s\n' SERVICE UNIT ACTIVE ENABLED
        for svc in "${SERVICES[@]}"; do
            unit="$(unit_of "$svc").service"
            if [[ -f "/etc/systemd/system/$unit" ]]; then
                printf '%-10s %-22s %-10s %s\n' "$svc" "$unit" \
                    "$(systemctl is-active "$unit" || true)" \
                    "$(systemctl is-enabled "$unit" || true)"
            else
                printf '%-10s %-22s %s\n' "$svc" "$unit" "not installed"
            fi
        done
        ;;
    logs)
        args=()
        for svc in "${SERVICES[@]}"; do
            args+=(-u "$(unit_of "$svc").service")
        done
        exec journalctl -f "${args[@]}"
        ;;
    delete)
        for svc in "${REVERSED[@]}"; do
            step "delete $svc"
            "$DAAS_INSTALLER_DIR/$svc/delete.bash" $PURGE
        done
        ;;
    *)
        usage
        ;;
esac
