# PostgreSQL, the one database server of the stack (see README.md):
#   mergedb         the DaaS backend (src/config/db.toml)
#   design_backend  the auth service (AUTH_DB_NAME, created by auth-install)
# The DaaS backend starts it as daas-0-postgres on 127.0.0.1:5432, data in
# src/data/db/postgres (src/config/container.toml).

# 18: the current major version. Never lower it on an existing data
# directory (PostgreSQL cannot read a newer one); an upgrade to 19 needs
# pg_upgrade or a dump and restore.
FROM postgres:18

# All of these are only applied when the data directory is created (first
# start):
# - the superuser password: DAAS_DB_PASSWORD from installer/daas.env, also
#   written to db.toml by daas-configure
# - the database mergedb of the DaaS backend
# - pg_hba.conf: logins over the network only from the docker host
#   (connections to the published 127.0.0.1:5432 arrive from the bridge
#   gateway), not from the instances, which share the docker bridge
# - only the superuser may connect to mergedb
ARG SUPERUSER_PASSWORD
ENV POSTGRES_PASSWORD=${SUPERUSER_PASSWORD}
ENV POSTGRES_DB=mergedb
COPY pg_hba.conf /etc/daas/pg_hba.conf
COPY init.sh /docker-entrypoint-initdb.d/
