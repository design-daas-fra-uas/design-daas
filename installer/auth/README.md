# auth: users, login and permissions (auth service)

Installs the **auth service** (its own repository,
`design-daas-backend-java`, Spring Boot) as `daas-auth.service`. It owns
the users, groups, OAuth tokens and permissions, kept in the database
`AUTH_DB_NAME` of the stack's one MariaDB (`daas-0-mariadb`,
[`../mariadb`](../mariadb/README.md), next to the DaaS backend's `mergedb`):

- the **frontend** logs users in through it (`AUTH_PUBLIC_URL`, nginx
  `/auth/` on :8443)
- the **DaaS backend** logs in with the admin account to check users and
  permissions (`127.0.0.1:AUTH_PORT`, `src/config/auth.toml`)

```
frontend (browser) ─https :8443/auth/─ nginx ─┐
DaaS backend ──────── http 127.0.0.1:8080 ────┴─ daas-auth ── daas-0-mariadb 127.0.0.1:3306
                                                 (host network,     database design_backend
                                                  volume keys)      (MariaDB 11.4)
```

## Settings (`installer/daas.env`)

| Setting | Used for |
|---|---|
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | Admin account, **created only on the very first start** (empty database) |
| `AUTH_DB_NAME`, `AUTH_DB_USER`, `AUTH_DB_PASSWORD` | Its database and user in `daas-0-mariadb` (the user may only log in from the docker host `172.17.0.1` and only use this database) |
| `AUTH_PORT` | Port on 127.0.0.1 (default 8080) |
| `AUTH_PROFILE` | `prod`, or `dev` for Swagger UI on `/auth/swagger-ui.html` |
| `AUTH_PUBLIC_URL` | Token issuer; `FRONTEND_PUBLIC_URL`: allowed CORS origin and links in mails |
| `OAUTH_ACCESS_TOKEN_TTL_SECONDS`, `OAUTH_REFRESH_TOKEN_TTL_DAYS` | Token lifetimes |
| `MAIL_*` | Registration mails (optional) |

`auth-install` writes them to `auth/.env` (mode 600) for docker-compose.
`ADMIN_PASSWORD` is only read when the admin is created (first start), and
the auth service has no password change of its own: after changing it in
`daas.env`, run `make auth-admin-password` (below). `make auth-install`
creates the database and user if missing and sets `AUTH_DB_PASSWORD` every
time.

## Commands

From `installer/`, as root:

| Command | What it does |
|---|---|
| `make auth-install` | Starts `daas-0-mariadb` if needed and creates the database and user there, builds the image from the current Java code (Maven inside docker), writes the unit, (re)starts and waits until it answers, then tests the admin login |
| `make auth-check` | Tests the running backend (changes nothing): service, containers, its database, admin login directly **and** through nginx `/auth/`, the keys volume, and that user instances cannot reach it directly |
| `make auth-backup` | Saves the database and the signing keys to `auth/backups/` (below) |
| `make auth-admin-password` | Sets the admin password to `ADMIN_PASSWORD` (BCrypt hash made in a throwaway container, never printed) and revokes all the admin's tokens; then `make daas-configure daas-restart` |
| `make auth-status` / `auth-logs` / `auth-restart` | Service control |
| `make auth-reinstall` | Delete + install from the current code; users and keys are kept |
| `make auth-delete [PURGE=1]` | Removes service, container and image. `PURGE=1` also drops the **database, its user and the keys**: all users and permissions are gone. Run `make auth-backup` first |

Restarting it does not restart the DaaS backend; logins fail while the
auth service starts (about 8 s on this host, after the database is up).

The DaaS backend starts and stops `daas-0-mariadb`, so the auth service is
down while the DaaS backend is stopped: its container exits and docker
restarts it until the database is back. `make auth-start` starts the
database container first.

## Backup and restore

`make auth-backup` (works while it runs) creates, root-only:

- `auth/backups/db-<time>.sql.gz`: its database `AUTH_DB_NAME` (users,
  groups, tokens, permissions, schema version), not `mergedb`
- `auth/backups/keys-<time>.tar.gz`: the token signing key (`rsa-jwk.json`);
  without it every issued token becomes invalid

It checks the dump (valid gzip, tables present) and the key archive. A dump
of this kind was used on 2026-11-17 to move the data from the old separate
auth MariaDB into `daas-0-mariadb` (checksums of all 17 tables equal).

Restore (replaces the current users and permissions):

```bash
cd /root/design-daas/installer/auth
systemctl stop daas-auth                                       # removes the container, keeps the keys volume
gzip -dc backups/db-<time>.sql.gz | docker exec -i daas-0-mariadb sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"'
docker run --rm -i -v daas-auth_keys:/k mariadb:11.4 tar -C /k -xzf - < backups/keys-<time>.tar.gz
systemctl start daas-auth && make -C .. auth-check
```

## Security

- The container runs on the host network (to reach `127.0.0.1:3306`) and
  the app listens on `127.0.0.1:AUTH_PORT` only (`SERVER_ADDRESS`).
  `auth-check` verifies that user instances (default docker bridge) cannot
  reach it; VMs cannot reach the host's 8080 either.
- Its database user has rights on `AUTH_DB_NAME` only, so it cannot read or
  change the DaaS backend's `mergedb`.
- nginx overwrites `X-Forwarded-For` with the real client address, so the
  login rate limit cannot be bypassed by sending that header. The auth service
  trusts the header from `127.0.0.1` only (`RATE_LIMIT_TRUSTED_PROXIES`),
  where nginx connects from.
- The auth service container runs as root inside the container (image default).

## Files

| File | Content |
|---|---|
| `install.bash` | Database + user in `daas-0-mariadb`, `.env` from `daas.env`, image build, `daas-auth.service`, wait + admin login test |
| `delete.bash` | Removes service, container, image (`-p`: also the database, its user, the keys volume and `.env`) |
| `check.bash` | The test behind `make auth-check` |
| `backup.bash` | The backup behind `make auth-backup` |
| `set-admin-password.bash` | The password change behind `make auth-admin-password` |
| `docker-compose.yml` | The container, keys volume, environment |
| `.env`, `backups/` | Generated, root-only, not committed |
