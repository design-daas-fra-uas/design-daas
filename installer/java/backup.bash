#!/usr/bin/env bash
#
# Backs up the Java backend's data while it runs (see README.md):
#   db-<time>.sql.gz    the database: all users, roles and permissions
#   keys-<time>.tar.gz  the token signing keys (without them every issued
#                       token becomes invalid)
# into installer/java/backups/ (root only, not committed). The passwords
# stay inside the containers and never show up in the log.
#
# Usage: ./backup.bash [<backup-folder>]

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"

BACKUP_DIR="${1:-$DAAS_INSTALLER_DIR/java/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DB_FILE="$BACKUP_DIR/db-$STAMP.sql.gz"
KEYS_FILE="$BACKUP_DIR/keys-$STAMP.tar.gz"

require_root
require_cmds docker gzip tar
for c in daas-java-db daas-java-backend; do
    [[ -n "$(docker ps -q --filter "name=^$c$")" ]] || die "$c is not running (make java-start)"
done

mkdir -p -m 700 "$BACKUP_DIR"
umask 077

step "Database -> $DB_FILE"
# --single-transaction: a consistent dump without locking the running app
docker exec daas-java-db sh -c 'exec mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" \
    --single-transaction --routines --triggers --databases "$MARIADB_DATABASE"' \
    | gzip > "$DB_FILE"
gzip -t "$DB_FILE" || die "The database dump is broken"
tables="$(gzip -dc "$DB_FILE" | grep -c '^CREATE TABLE')"
(( tables > 0 )) || die "The database dump has no tables"
success "$tables tables, $(du -h "$DB_FILE" | cut -f1)"

step "Signing keys -> $KEYS_FILE"
docker exec daas-java-backend tar -C /app/keys -czf - . > "$KEYS_FILE"
files="$(tar -tzf "$KEYS_FILE" | grep -vc '/$')"
(( files > 0 )) || die "No signing keys found in /app/keys"
success "$files files"

success "Backup done: $DB_FILE $KEYS_FILE"
