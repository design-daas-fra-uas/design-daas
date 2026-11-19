# postgres: the database of the whole stack

PostgreSQL **18**, the one database server of the stack:

| Database | Used by | Content |
|---|---|---|
| `mergedb` | **DaaS backend** (`src/config/db.toml`, `db_type = "postgres"`) | VMs, containers, instances, apps, files and limits |
| `design_backend` (`AUTH_DB_NAME`) | **auth service** ([`../auth`](../auth/README.md)) | users, groups, OAuth tokens, permissions |

## How it is used

- Container **`daas-0-postgres`** from image **`daas-0-postgres`**, started and
  stopped by the DaaS backend with its other service containers
  (`src/config/container.toml`), 2 CPUs, 2 GiB.
- Port `127.0.0.1:5432` (only this host); data in `src/data/db/postgres`.
- The backend connects as the superuser `postgres` with `DAAS_DB_PASSWORD`
  (from `src/config/local/db.toml`, not in git) to `mergedb`, and creates
  missing tables itself on start. It waits up to 60 s for PostgreSQL to
  accept connections after starting the container.
- The auth service connects as its own user `AUTH_DB_USER`, which owns
  `AUTH_DB_NAME` and may not connect to `mergedb`; `make auth-install`
  creates both. Its schema is managed by Flyway in the Java repository.
  Since the DaaS backend starts and stops this container, the auth service
  is down while the DaaS backend is stopped (`make auth-start` starts the
  container first; the auth service reconnects on its own).

## Security

All of these are applied when the data folder is created (first start,
`init.sh`):

- the superuser password `DAAS_DB_PASSWORD` from `installer/daas.env` (baked
  into the image; only root and the docker group can read images)
- `pg_hba.conf`: network logins only from the docker host (`172.17.0.1`,
  the address connections to the published port arrive from), **not from
  the user instances**, which share the docker bridge with this container
- only the superuser may connect to `mergedb`

Never lower the major version on an existing data folder. Moving to a newer
major version (19) needs `pg_upgrade` or a dump and restore.

## Commands

From `installer/` (normal use):

```bash
make db-install       # build the image; restarts a running container only if the image changed
make db-status        # running / stopped / not installed
make db-logs          # follow the PostgreSQL log
make db-restart       # restart (the backend reconnects; better: make daas-restart)
```

From `installer/postgres/`, as root:

| Command | What it does |
|---|---|
| `make build` | Builds `daas-0-postgres` with `DAAS_DB_PASSWORD` from `../daas.env` |
| `make check` | Starts a test container with its own empty data folder on 127.0.0.1:15432 (does not touch `daas-0-postgres`), checks the version, the database, that logins work from the host but **not** from the docker bridge, and that a wrong password is refused. Removes it again |
| `make clean` | Removes the image |

Look inside (`design_backend` for the auth service):

```bash
docker exec -it daas-0-postgres psql -U postgres mergedb
```

## Changing the password

`DAAS_DB_PASSWORD` only takes effect for a new data folder. On a running
system, change it in PostgreSQL too
(`docker exec -it daas-0-postgres psql -U postgres -c '\password postgres'`),
then `make db-install daas-configure daas-restart`.

## History

- Until 2026-11-05 the backend used SQLite (`src/data/db/sqlite/mergedb.sqlite3`,
  kept unchanged; it is still supported with `db_type = "sqlite"`).
- 2026-11-05 to 2026-11-17 it used MariaDB 11.4 (`daas-0-mariadb`,
  `installer/mariadb` in git history). On 2026-11-17 the auth service's own
  MariaDB was first merged into it, and the same day both databases were
  moved here. Every row of all 7 `mergedb` and 16 `design_backend` tables
  was compared after the copy. The MariaDB data folder
  `src/data/db/mariadb` was kept as it was.

## Files

| File | Content |
|---|---|
| `Dockerfile` | `postgres:18` + superuser password + `mergedb` |
| `pg_hba.conf` | Who may log in from where |
| `init.sh` | First start: installs `pg_hba.conf`, takes CONNECT on `mergedb` away from other users |
| `Makefile` | build, check, clean |
| `check.bash` | Smoke test behind `make check` |
