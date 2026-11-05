# MariaDB for the DaaS backend (see README.md), only used when
# src/config/db.toml has db_type = "mariadb". The DaaS backend starts it as
# daas-0-db on 127.0.0.1:3306, data in src/data/db/mariadb
# (src/config/container.toml).

# 11.4: LTS, the same version as the Java backend's database. Never lower it
# on an existing data directory (MariaDB cannot downgrade one).
FROM mariadb:11.4

# Both are only applied when the data directory is created (first start):
# - the root password: DAAS_DB_PASSWORD from installer/daas.env, also
#   written to db.toml by daas-configure
# - root may only log in from the docker host (connections to the published
#   127.0.0.1:3306 arrive from the bridge gateway), not from the instances,
#   which share the docker bridge with this container
ARG ROOT_PASSWORD
ENV MARIADB_ROOT_PASSWORD=${ROOT_PASSWORD}
ENV MARIADB_ROOT_HOST=172.17.0.1
