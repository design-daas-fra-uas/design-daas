# mariadb: the DaaS backend's database

MariaDB **11.4** (LTS) for the **DaaS backend**: VMs, containers, instances,
apps, files and limits (`src/config/db.toml`, `db_type = "mariadb"`).
Separate from the auth service's own MariaDB (`daas-auth-db`).

## How it is used

- Container **`daas-0-mariadb`** from image **`daas-0-mariadb`**, started and
  stopped by the DaaS backend with its other service containers
  (`src/config/container.toml`), 2 CPUs, 2 GiB.
- Port `127.0.0.1:3306` (only this host); data in `src/data/db/mariadb`.
- The backend connects as `root` with `DAAS_DB_PASSWORD` (from
  `src/config/local/db.toml`, not in git) to the database `mergedb`, and
  creates missing tables itself on start. It waits up to 60 s for MariaDB
  to accept connections after starting the container.

## Security

Both settings are applied when the data folder is created (first start):

- the root password `DAAS_DB_PASSWORD` from `installer/daas.env` (baked into
  the image; only root and the docker group can read images)
- root may only log in from the docker host (`MARIADB_ROOT_HOST=172.17.0.1`,
  the address connections to the published port arrive from), **not from
  the user instances**, which share the docker bridge with this container

Never lower the version on an existing data folder: MariaDB cannot
downgrade one.

## Commands

From `installer/` (normal use):

```bash
make db-install       # build the image; restarts a running container only if the image changed
make db-status        # running / stopped / not installed
make db-logs          # follow the MariaDB log
make db-restart       # restart (the backend reconnects; better: make daas-restart)
```

From `installer/mariadb/`, as root:

| Command | What it does |
|---|---|
| `make build` | Builds `daas-0-mariadb` with `DAAS_DB_PASSWORD` from `../daas.env` |
| `make check` | Starts a test container with its own empty data folder on 127.0.0.1:13306 (does not touch `daas-0-mariadb`), checks the version, that root logs in from the host but **not** from the docker bridge, and that the old public password is refused. Removes it again |
| `make clean` | Removes the image |

Look inside:

```bash
docker exec -it daas-0-mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" mergedb'
```

## Changing the password

`DAAS_DB_PASSWORD` only takes effect for a new data folder. On a running
system, change it in MariaDB too
(`ALTER USER 'root'@'172.17.0.1' IDENTIFIED BY '...'`), then
`make db-install daas-configure daas-restart`.

## History

Until 2026-11-05 the backend used SQLite (`src/data/db/sqlite/mergedb.sqlite3`)
and this container ran unused, with a public root password. the SQLite file
is kept unchanged as a fallback (switch back: `db_type = "sqlite"` in
`src/config/db.toml`, `make daas-restart`).

## Files

| File | Content |
|---|---|
| `Dockerfile` | `mariadb:11.4` + root password + root only from the host |
| `Makefile` | build, check, clean |
| `check.bash` | Smoke test behind `make check` |
