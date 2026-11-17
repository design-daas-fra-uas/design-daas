#!/usr/bin/env bash
#
# Backs up the auth service's data while it runs (see README.md):
#   db-<time>.sql.gz    its database AUTH_DB_NAME in the DaaS PostgreSQL: all
#                       users, roles and permissions
#   keys-<time>.tar.gz  the token signing keys (without them every issued
#                       token becomes invalid)
# into installer/auth/backups/ (root only, not committed). The passwords
# stay inside the containers and never show up in the log.
#
# Usage: ./backup.bash -e <env-file> [<backup-folder>]

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

ENV_FILE=""
while getopts ":e:" o; do
    case "$o" in
        e) ENV_FILE="$OPTARG" ;;
        *) echo "Usage: $0 -e <env-file> [<backup-folder>]" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
[[ -n "$ENV_FILE" ]] || { echo "Usage: $0 -e <env-file> [<backup-folder>]" >&2; exit 1; }

BACKUP_DIR="${1:-$DAAS_INSTALLER_DIR/auth/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DB_FILE="$BACKUP_DIR/db-$STAMP.sql.gz"
KEYS_FILE="$BACKUP_DIR/keys-$STAMP.tar.gz"

require_root
require_cmds docker gzip tar
load_stack_env "$ENV_FILE" >/dev/null
[[ "$AUTH_DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || die "Unexpected characters in AUTH_DB_NAME"
for c in "$DAAS_DB_CONTAINER" daas-auth; do
    [[ -n "$(docker ps -q --filter "name=^$c$")" ]] || die "$c is not running (make auth-start)"
done

mkdir -p -m 700 "$BACKUP_DIR"
umask 077

step "Database $AUTH_DB_NAME -> $DB_FILE"
# pg_dump reads one snapshot: consistent without locking the running app.
# --create: the dump creates the database itself on restore
docker exec "$DAAS_DB_CONTAINER" pg_dump -U postgres --create "$AUTH_DB_NAME" \
    | gzip > "$DB_FILE"
gzip -t "$DB_FILE" || die "The database dump is broken"
tables="$(gzip -dc "$DB_FILE" | grep -c '^CREATE TABLE')"
(( tables > 0 )) || die "The database dump has no tables"
success "$tables tables, $(du -h "$DB_FILE" | cut -f1)"

step "Signing keys -> $KEYS_FILE"
docker exec daas-auth tar -C /app/keys -czf - . > "$KEYS_FILE"
files="$(tar -tzf "$KEYS_FILE" | grep -vc '/$')"
(( files > 0 )) || die "No signing keys found in /app/keys"
success "$files files"

success "Backup done: $DB_FILE $KEYS_FILE"
