# auth: users, login and permissions (auth service)

Installs the **auth service** (its own repository,
`design-daas-backend-java`, Spring Boot) with **its own MariaDB** as
`daas-auth.service`. It owns the users, groups, OAuth tokens and
permissions:

- the **frontend** logs users in through it (`AUTH_PUBLIC_URL`, nginx
  `/auth/` on :8443)
- the **DaaS backend** logs in with the admin account to check users and
  permissions (`127.0.0.1:AUTH_PORT`, `src/config/auth.toml`)

```
frontend (browser) ─https :8443/auth/─ nginx ─┐
DaaS backend ──────── http 127.0.0.1:8080 ────┴─ daas-auth ── daas-auth-db (MariaDB 11.4)
                                                 (network daas-auth_default, volumes db-data + keys)
```

## Settings (`installer/daas.env`)

| Setting | Used for |
|---|---|
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | Admin account, **created only on the very first start** (empty database) |
| `AUTH_DB_NAME`, `AUTH_DB_USER`, `AUTH_DB_PASSWORD`, `AUTH_DB_ROOT_PASSWORD` | Its MariaDB (also only applied when the database is created) |
| `AUTH_PORT` | Port on 127.0.0.1 (default 8080) |
| `AUTH_PROFILE` | `prod`, or `dev` for Swagger UI on `/auth/swagger-ui.html` |
| `AUTH_PUBLIC_URL` | Token issuer; `FRONTEND_PUBLIC_URL`: allowed CORS origin and links in mails |
| `OAUTH_ACCESS_TOKEN_TTL_SECONDS`, `OAUTH_REFRESH_TOKEN_TTL_DAYS` | Token lifetimes |
| `MAIL_*` | Registration mails (optional) |

`auth-install` writes them to `auth/.env` (mode 600) for docker-compose.
`ADMIN_PASSWORD` is only read when the admin is created (first start), and
the auth service has no password change of its own: after changing it in
`daas.env`, run `make auth-admin-password` (below). The DB passwords are
only applied when the database is created.

## Commands

From `installer/`, as root:

| Command | What it does |
|---|---|
| `make auth-install` | Builds the image from the current Java code (Maven inside docker), writes the unit, (re)starts and waits until it answers, then tests the admin login |
| `make auth-check` | Tests the running backend (changes nothing): service, containers (DB healthy), admin login directly **and** through nginx `/auth/`, the data volumes, and that user instances cannot reach it directly |
| `make auth-backup` | Saves the database and the signing keys to `auth/backups/` (below) |
| `make auth-admin-password` | Sets the admin password to `ADMIN_PASSWORD` (BCrypt hash made in a throwaway container, never printed) and revokes all the admin's tokens; then `make daas-configure daas-restart` |
| `make auth-status` / `auth-logs` / `auth-restart` | Service control |
| `make auth-reinstall` | Delete + install from the current code; users and keys are kept |
| `make auth-delete [PURGE=1]` | Removes service, containers and image. `PURGE=1` also deletes the **database and keys**: all users and permissions are gone. Run `make auth-backup` first |

Restarting it does not restart the DaaS backend; logins fail while the
auth service starts (about 8 s on this host, after the database is up).

## Backup and restore

`make auth-backup` (works while it runs) creates, root-only:

- `auth/backups/db-<time>.sql.gz`: the whole database (users, groups,
  tokens, permissions, schema version)
- `auth/backups/keys-<time>.tar.gz`: the token signing key (`rsa-jwk.json`);
  without it every issued token becomes invalid

It checks the dump (valid gzip, tables present) and the key archive. The
dump was tested by restoring it into a separate MariaDB 11.4: same users
and tables as the live database.

Restore (replaces the current users and permissions):

```bash
cd /root/design-daas/installer/auth
systemctl stop daas-auth                                       # removes the containers, keeps the volumes
docker-compose --env-file .env -f docker-compose.yml up -d db  # only the database
gzip -dc backups/db-<time>.sql.gz | docker exec -i daas-auth-db sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"'
docker run --rm -i -v daas-auth_keys:/k mariadb:11.4 tar -C /k -xzf - < backups/keys-<time>.tar.gz
docker-compose --env-file .env -f docker-compose.yml down
systemctl start daas-auth && make -C .. auth-check
```

## Security

- Port 8080 is published on `127.0.0.1` only; the containers are on their
  own docker network. `auth-check` verifies that user instances (default
  docker bridge) cannot reach it; VMs cannot reach the host's 8080 either.
- nginx overwrites `X-Forwarded-For` with the real client address, so the
  login rate limit cannot be bypassed by sending that header. The auth service
  trusts the header from docker networks
  (`RATE_LIMIT_TRUSTED_PROXIES`), which only nginx can reach.
- The auth service container runs as root inside the container (image default).

## Files

| File | Content |
|---|---|
| `install.bash` | `.env` from `daas.env`, image build, `daas-auth.service`, wait + admin login test |
| `delete.bash` | Removes service, containers, image (`-p`: also the volumes and `.env`) |
| `check.bash` | The test behind `make auth-check` |
| `backup.bash` | The backup behind `make auth-backup` |
| `set-admin-password.bash` | The password change behind `make auth-admin-password` |
| `docker-compose.yml` | The two containers, network, volumes, environment |
| `.env`, `backups/` | Generated, root-only, not committed |
