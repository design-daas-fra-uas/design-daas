#!/bin/sh
# Runs once, when the data directory is created (docker-entrypoint-initdb.d,
# as user postgres, with a temporary server on the socket):
# - replace the image's default pg_hba.conf (any address with a password)
#   with ours; read when the final server starts
# - only the superuser may connect to mergedb, not the auth service's user
set -e
cp /etc/daas/pg_hba.conf "$PGDATA/pg_hba.conf"
psql -v ON_ERROR_STOP=1 -U postgres -d postgres -q \
    -c 'REVOKE CONNECT, TEMPORARY ON DATABASE mergedb FROM PUBLIC'
