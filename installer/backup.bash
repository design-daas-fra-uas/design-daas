#!/usr/bin/env bash
#
# Backs up all data of the running system into one folder
# installer/backups/<time>/ (root only, not committed):
#   postgres.sql.gz     the whole DaaS PostgreSQL (daas-0-postgres): the DaaS
#                       backend's database mergedb, the auth service's
#                       database (users, groups, permissions) and their roles
#   auth-keys.tar.gz    the auth service's token signing keys (without them
#                       every issued token becomes invalid)
#
# Only needed before deleting data (make reset, make <x>-delete PURGE=1);
# README.md "Backup and restore" shows how to restore it. Works while the
# system runs. The passwords stay inside the containers.
#
# Usage: ./backup.bash [<backup-folder>]

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.bash"

(( $# <= 1 )) || { echo "Usage: $0 [<backup-folder>]" >&2; exit 1; }
BACKUP_DIR="${1:-$DAAS_INSTALLER_DIR/backups/$(date +%Y%m%d-%H%M%S)}"
DB_FILE="$BACKUP_DIR/postgres.sql.gz"
KEYS_FILE="$BACKUP_DIR/auth-keys.tar.gz"

require_root
require_cmds docker gzip tar
for c in "$DAAS_DB_CONTAINER" daas-auth; do
    [[ -n "$(docker ps -q --filter "name=^$c$")" ]] || die "$c is not running (make start)"
done

mkdir -p -m 700 "$(dirname "$BACKUP_DIR")" "$BACKUP_DIR"
umask 077

step "PostgreSQL ($DAAS_DB_CONTAINER) -> $DB_FILE"
# pg_dumpall: every database plus the roles, each database from one snapshot.
# --clean --if-exists: the restore drops and recreates them, so it also works
# on a system that already has (other) data
docker exec "$DAAS_DB_CONTAINER" pg_dumpall -U postgres --clean --if-exists | gzip > "$DB_FILE"
gzip -t "$DB_FILE" || die "The database dump is broken"
dbs="$(gzip -dc "$DB_FILE" | grep -c '^CREATE DATABASE')"
(( dbs > 0 )) || die "The database dump contains no database"
success "$dbs databases, $(du -h "$DB_FILE" | cut -f1)"

step "auth service signing keys -> $KEYS_FILE"
docker exec daas-auth tar -C /app/keys -czf - . > "$KEYS_FILE"
files="$(tar -tzf "$KEYS_FILE" | grep -vc '/$')"
(( files > 0 )) || die "No signing keys found in /app/keys"
success "$files files"

success "Backup done: $BACKUP_DIR"
