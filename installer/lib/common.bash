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
        command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
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

# set_toml_value FILE KEY VALUE: set `KEY = "VALUE"` in FILE.
# The key is matched by name, so this works whatever the current value is
# and can be re-run with different values.
set_toml_value() {
    local file="$1" key="$2" value="$3" current new
    require_file "$file"
    if ! current="$(grep -m1 -E "^[[:space:]]*${key}[[:space:]]*=" "$file")"; then
        warn "Key '$key' not found in $file, skipping"
        return 0
    fi
    new="${key} = \"${value}\""
    if [[ "$current" == "$new" ]]; then
        info "$(basename "$file"): $key already \"$value\""
        return 0
    fi
    sed -i -E "0,/^[[:space:]]*${key}[[:space:]]*=/s#^[[:space:]]*${key}[[:space:]]*=.*#${new//&/\\&}#" "$file"
    success "$(basename "$file"): ${current} -> ${new}"
}

# enable_and_restart UNIT...: enable units, (re)start them and verify they run
enable_and_restart() {
    local unit
    for unit in "$@"; do
        run systemctl enable "$unit"
        run systemctl restart "$unit"
        if systemctl is-active --quiet "$unit"; then
            success "Service running: $unit"
        else
            systemctl status --no-pager "$unit" || true
            die "Service failed to start: $unit"
        fi
    done
}
