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
DAAS_DEBUG="${DAAS_DEBUG:-0}"

if [[ -n "$DAAS_LOG_FILE" ]]; then
    if ! { mkdir -p "$(dirname "$DAAS_LOG_FILE")" && touch "$DAAS_LOG_FILE"; } 2>/dev/null; then
        printf 'WARN: cannot write log file %s, logging to console only\n' "$DAAS_LOG_FILE" >&2
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

# write_file PATH: write stdin to PATH and log whether it changed
write_file() {
    local target="$1" tmp
    tmp="$(mktemp)"
    cat > "$tmp"
    if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
        rm -f "$tmp"
        info "Unchanged: $target"
        return 0
    fi
    mkdir -p "$(dirname "$target")"
    mv "$tmp" "$target"
    chmod 644 "$target"
    success "Wrote: $target"
}

# set_toml_value FILE KEY VALUE [raw]: set `KEY = "VALUE"` in FILE
# (with "raw": `KEY = VALUE`, for booleans and numbers).
# The first line starting with KEY is replaced, so this works whatever the
# current value is and can be re-run with different values. VALUE may hold
# any character; it is escaped for TOML. Keys whose name contains
# "password" are not printed in the log.
set_toml_value() {
    local file="$1" key="$2" value="$3" mode="${4:-string}" current new shown tmp
    require_file "$file"
    if ! current="$(grep -m1 -E "^[[:space:]]*${key}[[:space:]]*=" "$file")"; then
        warn "Key '$key' not found in $file, skipping"
        return 0
    fi
    if [[ "$mode" == raw ]]; then
        new="${key} = ${value}"
    else
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        new="${key} = \"${value}\""
    fi
    shown="$new"
    if [[ "$key" == *password* ]]; then
        shown="${key} = <hidden>"
    fi
    if [[ "$current" == "$new" ]]; then
        info "$(basename "$file"): $shown (unchanged)"
        return 0
    fi
    tmp="$(mktemp)"
    # Replacement via ENVIRON: awk -v would interpret backslashes
    NEW_LINE="$new" awk -v key="$key" '
        !done && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { print ENVIRON["NEW_LINE"]; done = 1; next }
        { print }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
    if [[ "$key" == *password* ]]; then
        success "$(basename "$file"): $shown"
    else
        success "$(basename "$file"): ${current} -> ${new}"
    fi
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

    [[ -n "${HOST_NAME:-}" ]] || die "HOST_NAME is not set in $file"
    [[ -n "${HOST_DOMAIN:-}" ]] || die "HOST_DOMAIN is not set in $file"
    export FQDN="$HOST_NAME.$HOST_DOMAIN"

    export FRONTEND_FOLDER="${FRONTEND_FOLDER:-$(dirname "$repo")/design-daas-application-frontend}"
    export JAVA_BACKEND_FOLDER="${JAVA_BACKEND_FOLDER:-$(dirname "$repo")/design-daas-backend-java}"
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
    export JAVA_PORT="${JAVA_PORT:-8080}"
    export JAVA_PROFILE="${JAVA_PROFILE:-prod}"

    [[ "$DAAS_AUTH_MODE" == remote || "$DAAS_AUTH_MODE" == local ]] \
        || die "DAAS_AUTH_MODE must be 'remote' or 'local' (got '$DAAS_AUTH_MODE')"
    [[ "$DAAS_AUTH_CHECK_ENDPOINTS" == true || "$DAAS_AUTH_CHECK_ENDPOINTS" == false ]] \
        || die "DAAS_AUTH_CHECK_ENDPOINTS must be 'true' or 'false'"
    [[ "$JAVA_PORT" =~ ^[0-9]+$ ]] || die "JAVA_PORT must be a number (got '$JAVA_PORT')"

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
    local file="$1" key value
    shift
    {
        echo "# Generated by the Design DaaS installer. Do not edit."
        for key in "$@"; do
            value="${!key:-}"
            [[ "$value" != *"'"* ]] || die "$key must not contain a single quote (')"
            printf "%s='%s'\n" "$key" "$value"
        done
    } | write_file "$file"
    chmod 600 "$file"
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

# wait_http URL [TRIES]: wait until URL gives any HTTP answer (5s per try,
# default 60 tries). Returns 1 on timeout.
wait_http() {
    local url="$1" tries="${2:-60}" i code
    for (( i = 1; i <= tries; i++ )); do
        code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$url" || true)"
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
