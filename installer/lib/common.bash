#!/usr/bin/env bash
#
# Shared helpers for the Design DaaS installer scripts.
#
# Usage (at the top of a script):
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"
#
# Provides:
#   - strict mode (set -Eeuo pipefail) with an ERR trap that reports the
#     failing command, line and exit code
#   - leveled, timestamped logging: debug/info/success/warn/error/die/step
#   - run: logs a command before executing it
#   - every message is also appended to $DAAS_LOG_FILE
#     (default: /var/log/daas-installer.log, disable with DAAS_LOG_FILE=)
#   - DAAS_DEBUG=1 enables debug messages and shell tracing (set -x)

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
DAAS_INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEBIAN_FRONTEND=noninteractive

# ============================================================
# Logging
# ============================================================

DAAS_LOG_FILE="${DAAS_LOG_FILE-/var/log/daas-installer.log}"
# Set by write_file (see there)
WRITE_FILE_CHANGED=0
DAAS_DEBUG="${DAAS_DEBUG:-0}"

if [[ -n "$DAAS_LOG_FILE" ]]; then
    if ! { mkdir -p "$(dirname "$DAAS_LOG_FILE")" && touch "$DAAS_LOG_FILE"; } 2>/dev/null; then
        # Normal users (make status, make help) cannot write it: no warning
        [[ "$EUID" -ne 0 ]] || printf 'WARN: cannot write log file %s, logging to console only\n' "$DAAS_LOG_FILE" >&2
        DAAS_LOG_FILE=""
    fi
fi

if [[ -t 1 ]]; then
    _C_RESET=$'\e[0m'; _C_DIM=$'\e[2m'; _C_RED=$'\e[31m'; _C_BOLD=$'\e[1m'
    _C_GREEN=$'\e[32m'; _C_YELLOW=$'\e[33m'; _C_BLUE=$'\e[34m'
else
    _C_RESET=""; _C_DIM=""; _C_RED=""; _C_BOLD=""
    _C_GREEN=""; _C_YELLOW=""; _C_BLUE=""
fi

# log LEVEL MESSAGE...
log() {
    local level="$1"
    shift
    local color line
    case "$level" in
        DEBUG)   color="$_C_DIM" ;;
        INFO)    color="$_C_BLUE" ;;
        SUCCESS) color="$_C_GREEN" ;;
        WARN)    color="$_C_YELLOW" ;;
        ERROR)   color="$_C_RED" ;;
        STEP)    color="$_C_BOLD" ;;
        *)       color="" ;;
    esac
    line="$(printf '[%s] [%-7s] [%s] %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$SCRIPT_NAME" "$*")"
    if [[ "$level" == WARN || "$level" == ERROR ]]; then
        printf '%s%s%s\n' "$color" "$line" "$_C_RESET" >&2
    else
        printf '%s%s%s\n' "$color" "$line" "$_C_RESET"
    fi
    if [[ -n "$DAAS_LOG_FILE" ]]; then
        printf '%s\n' "$line" >> "$DAAS_LOG_FILE"
    fi
}

debug()   { if [[ "$DAAS_DEBUG" == 1 ]]; then log DEBUG "$@"; fi; }
info()    { log INFO "$@"; }
success() { log SUCCESS "$@"; }
warn()    { log WARN "$@"; }
error()   { log ERROR "$@"; }
die()     { error "$@"; exit 1; }

# step TITLE: section header for the major phases of a script
step() {
    log STEP "==== $* ===="
}

# run CMD [ARGS...]: log the command, then execute it.
# The command's output goes to the console and is appended to the log file.
run() {
    local rc=0
    _DAAS_LAST_RUN="$*"
    info "\$ $*"
    if [[ -n "$DAAS_LOG_FILE" ]]; then
        "$@" 2>&1 | tee -a "$DAAS_LOG_FILE" || rc=$?
    else
        "$@" || rc=$?
    fi
    if (( rc != 0 )); then
        warn "Command exited with code $rc: $*"
    fi
    return "$rc"
}

# ============================================================
# Error handling
# ============================================================

_on_error() {
    local exit_code=$1 line=$2 cmd=$3
    # A failed `run` ends in its `return`; report the command it ran instead
    if [[ "$cmd" == 'return "$rc"' ]]; then
        cmd="${_DAAS_LAST_RUN:-$cmd}"
    fi
    error "Failed at line ${line} (exit code ${exit_code}): ${cmd}"
    if [[ -n "$DAAS_LOG_FILE" ]]; then
        error "Full log: $DAAS_LOG_FILE"
    fi
    exit "$exit_code"
}
trap '_on_error $? $LINENO "$BASH_COMMAND"' ERR

if [[ "$DAAS_DEBUG" == 1 ]]; then
    set -x
fi

# ============================================================
# Checks
# ============================================================

require_root() {
    [[ "$EUID" -eq 0 ]] || die "This script must be run as root."
}

# require_cmds CMD...: fail early if a required tool is missing
require_cmds() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd (install the dependencies: make deps)"
    done
}

require_dir() {
    [[ -d "$1" ]] || die "Directory does not exist: $1"
}

require_file() {
    [[ -f "$1" ]] || die "File does not exist: $1"
}

# ============================================================
# Helpers
# ============================================================

# apt_install PKG...: install packages non-interactively
apt_install() {
    run apt-get install -y "$@"
}

# write_file PATH [MODE]: write stdin to PATH (mode 644, or MODE, e.g. 600
# for files with secrets) and log whether it changed. Sets WRITE_FILE_CHANGED
# to 1/0 (not when called at the end of a pipe, which runs in a subshell).
# The file is written next to PATH with its final mode and then renamed, so
# it is never readable by others, not even for a moment.
write_file() {
    local target="$1" mode="${2:-644}" tmp
    WRITE_FILE_CHANGED=0
    mkdir -p "$(dirname "$target")"
    tmp="$(mktemp "$(dirname "$target")/.$(basename "$target").XXXXXX")"
    chmod "$mode" "$tmp"
    cat > "$tmp"
    if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
        rm -f "$tmp"
        chmod "$mode" "$target"
        info "Unchanged: $target"
        return 0
    fi
    mv "$tmp" "$target"
    WRITE_FILE_CHANGED=1
    success "Wrote: $target"
}

# toml_string VALUE: VALUE as a quoted TOML string (any character but a
# newline; backslashes and quotes escaped)
toml_string() {
    local value="$1"
    [[ "$value" != *$'\n'* ]] || die "A TOML value must not contain a newline"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

# load_env_file FILE: export KEY=value lines from FILE.
# Values are taken literally (no $ expansion, unlike `source`), so passwords
# may contain any character. Surrounding single/double quotes are removed.
load_env_file() {
    local file="$1" line key value
    require_file "$file"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            warn "$file: ignoring invalid line: $line"
            continue
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi
        export "$key=$value"
    done < "$file"
    info "Loaded settings from $file"
}

# load_stack_env FILE: load installer/daas.env and fill in derived defaults
# (folders, public URLs). See daas.env.example for the meaning of each key.
load_stack_env() {
    local file="$1" repo
    load_env_file "$file"
    repo="$(cd "$DAAS_INSTALLER_DIR/.." && pwd)"

    # Names from before the rename of "java" to "auth", still accepted
    local pair old new
    for pair in JAVA_BACKEND_FOLDER:AUTH_FOLDER JAVA_PORT:AUTH_PORT JAVA_PROFILE:AUTH_PROFILE \
            JAVA_DB_NAME:AUTH_DB_NAME JAVA_DB_USER:AUTH_DB_USER \
            JAVA_DB_PASSWORD:AUTH_DB_PASSWORD JAVA_DB_ROOT_PASSWORD:AUTH_DB_ROOT_PASSWORD; do
        old="${pair%%:*}" new="${pair##*:}"
        if [[ -n "${!old:-}" && -z "${!new:-}" ]]; then
            export "$new=${!old}"
            warn "$file: $old is now called $new, please rename it"
        fi
    done

    [[ -n "${HOST_NAME:-}" ]] || die "HOST_NAME is not set in $file"
    [[ -n "${HOST_DOMAIN:-}" ]] || die "HOST_DOMAIN is not set in $file"
    export FQDN="$HOST_NAME.$HOST_DOMAIN"

    export FRONTEND_FOLDER="${FRONTEND_FOLDER:-$(dirname "$repo")/design-daas-application-frontend}"
    export AUTH_FOLDER="${AUTH_FOLDER:-$(dirname "$repo")/design-daas-backend-java}"
    export DAAS_PUBLIC_URL="${DAAS_PUBLIC_URL:-https://$FQDN}"
    export FRONTEND_PUBLIC_URL="${FRONTEND_PUBLIC_URL:-https://$FQDN:8443}"
    export AUTH_PUBLIC_URL="${AUTH_PUBLIC_URL:-$FRONTEND_PUBLIC_URL/auth}"
    # No trailing slashes: the apps append "/path"
    DAAS_PUBLIC_URL="${DAAS_PUBLIC_URL%/}"
    FRONTEND_PUBLIC_URL="${FRONTEND_PUBLIC_URL%/}"
    AUTH_PUBLIC_URL="${AUTH_PUBLIC_URL%/}"

    export DAAS_AUTH_MODE="${DAAS_AUTH_MODE:-remote}"
    export DAAS_AUTH_CHECK_ENDPOINTS="${DAAS_AUTH_CHECK_ENDPOINTS:-false}"
    export OAUTH_CLIENT_ID="${OAUTH_CLIENT_ID:-test-client}"
    export AUTH_PORT="${AUTH_PORT:-8080}"
    export AUTH_PROFILE="${AUTH_PROFILE:-prod}"

    [[ "$DAAS_AUTH_MODE" == remote || "$DAAS_AUTH_MODE" == local ]] \
        || die "DAAS_AUTH_MODE must be 'remote' or 'local' (got '$DAAS_AUTH_MODE')"
    [[ "$DAAS_AUTH_CHECK_ENDPOINTS" == true || "$DAAS_AUTH_CHECK_ENDPOINTS" == false ]] \
        || die "DAAS_AUTH_CHECK_ENDPOINTS must be 'true' or 'false'"
    [[ "$AUTH_PORT" =~ ^[0-9]+$ ]] || die "AUTH_PORT must be a number (got '$AUTH_PORT')"

    debug "FQDN=$FQDN DAAS=$DAAS_PUBLIC_URL FRONTEND=$FRONTEND_PUBLIC_URL AUTH=$AUTH_PUBLIC_URL"
}

# url_host URL: the host name of URL (https://a.b:8443/x -> a.b)
url_host() {
    local rest="${1#*://}"
    rest="${rest%%/*}"
    echo "${rest%%:*}"
}

# url_port URL: the port of URL, or the default of its scheme
url_port() {
    local rest="${1#*://}"
    rest="${rest%%/*}"
    if [[ "$rest" == *:* ]]; then
        echo "${rest##*:}"
    elif [[ "$1" == https://* ]]; then
        echo 443
    else
        echo 80
    fi
}

# warn_default_secret NAME: warn if a secret still has its example value
warn_default_secret() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        die "$name is empty; set it in the env file"
    elif [[ "${!name}" == change-me* ]]; then
        warn "$name still has its example value, change it in the env file"
    fi
}

# write_compose_env FILE KEY...: write KEY='value' lines for docker-compose
# (--env-file) from the current environment. Values are single-quoted so
# compose takes them literally (no $ interpolation); a single quote cannot
# be escaped there. The file is mode 600, it may hold passwords.
write_compose_env() {
    local file="$1" key
    shift
    # Check first: a die inside the pipe below would only end a subshell
    for key in "$@"; do
        [[ "${!key:-}" != *"'"* ]] || die "$key must not contain a single quote (')"
    done
    {
        echo "# Generated by the Design DaaS installer. Do not edit."
        for key in "$@"; do
            printf "%s='%s'\n" "$key" "${!key:-}"
        done
    } | write_file "$file" 600
}

# check_active UNIT: fail with the unit's last log lines unless it is running
check_active() {
    local unit="$1"
    if systemctl is-active --quiet "$unit"; then
        success "Service running: $unit"
    else
        journalctl -u "$unit" -n 50 --no-pager || true
        die "Service failed to start: $unit"
    fi
}

# enable_and_restart UNIT...: enable units, (re)start them and verify they run
enable_and_restart() {
    local unit
    for unit in "$@"; do
        run systemctl enable "$unit"
        run systemctl restart "$unit"
        check_active "$unit"
    done
}

# The enterprise repositories need a paid subscription; without one
# `apt-get update` fails (401) and stops `make deps`. pve-manager (and
# pveceph) recreate the files, so their lines are commented out, not deleted.
disable_enterprise_repos() {
    local f
    for f in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/ceph.list; do
        [[ -f "$f" ]] || continue
        if grep -qE '^deb .*enterprise\.proxmox\.com' "$f"; then
            sed -i -E 's|^(deb .*enterprise\.proxmox\.com)|# \1|' "$f"
            success "Disabled the enterprise repository in $f (needs a subscription)"
        fi
    done
}

# reload_nginx: check the config, then reload a running nginx (keeps open
# connections, and services that depend on nginx keep running) or start it
reload_nginx() {
    run nginx -t
    run systemctl enable nginx
    if systemctl is-active --quiet nginx; then
        run systemctl reload nginx
    else
        run systemctl start nginx
    fi
    check_active nginx
}

# wait_http URL [TRIES]: wait until URL gives any HTTP answer (5s per try,
# default 60 tries). Returns 1 on timeout.
wait_http() {
    local url="$1" tries="${2:-60}" i code
    for (( i = 1; i <= tries; i++ )); do
        code="$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)"
        if [[ "$code" != 000 ]]; then
            success "$url answers (HTTP $code after $(( (i - 1) * 5 ))s)"
            return 0
        fi
        (( i % 6 == 0 )) && info "Still waiting for $url ($(( i * 5 ))s)..."
        sleep 5
    done
    return 1
}

# remove_unit NAME: stop, disable and delete /etc/systemd/system/NAME.service
remove_unit() {
    local unit="$1.service" file="/etc/systemd/system/$1.service"
    if [[ ! -f "$file" ]]; then
        info "$unit is not installed"
        return 0
    fi
    run systemctl disable --now "$unit"
    rm -f "$file"
    run systemctl daemon-reload
    systemctl reset-failed "$unit" 2>/dev/null || true
    success "Removed $unit"
}
