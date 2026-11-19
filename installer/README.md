# Design DaaS installer

Everything here is driven by `make`. Run all commands **as root** from this
folder (`installer/`). `make help` prints a short version of this page.

For a first install on a fresh Debian 12 (cloning, settings, installer,
browser setup), follow the step-by-step guide in the [top-level README](../README.md#installation-from-a-fresh-debian-12-to-a-running-system);
this page is the reference for all `make` targets.

## What you get

After `make install` one host runs the whole stack:

| Part | What it is | Where |
|---|---|---|
| Frontend | React web app the users work in (`frontend.service`) | `https://<host>:8443`, the only address users open |
| DaaS backend | Python API that creates and controls the instances (`daas.service`) | `127.0.0.1:5000`; nginx serves it on :443 of the same name, which the frontend calls in the background |
| auth service | Users, login (OAuth), permissions (`daas-auth.service`); data in the DaaS PostgreSQL (`daas-0-postgres`, database `design_backend`) | `127.0.0.1:8080`; the frontend reaches it through nginx as `/auth/` on :8443 |
| Proxmox VE | Runs the VM instances | host |
| Service containers | `guacd`, `rabbit`, `db` (PostgreSQL: the database of the DaaS backend and the auth service), `extensions`; started and stopped by the DaaS backend | docker |
| Desktop images | `x11vnc`, `wine`; the DaaS backend starts one container per instance | docker |
| ISOs | Unattended install ISOs (win10, win11, debian12) in the `daas-iso` storage | Proxmox |

`<host>` is `HOST_NAME.HOST_DOMAIN` from `daas.env` (e.g. `pve1.daas-design.de`).

## What you need

- A fresh **Debian 12** machine (VM or bare metal) with internet access,
  root access and enough disk for the docker images and ISOs.
- The two other repositories cloned **next to this one** (or set their paths
  in `daas.env`):

  ```
  /daas/design-daas                        this repo
  /daas/design-daas-application-frontend   FRONTEND_FOLDER
  /daas/design-daas-backend-java           AUTH_FOLDER
  ```
- `make`: `apt install make` if it is missing. Everything else is installed
  by the installer itself (step 2, `make deps`).

## Install, step by step

### 1. Create the settings file

```bash
cd /daas/design-daas/installer
make env
```

This copies `daas.env.example` to `daas.env` (mode 600, not committed). Edit it:

- **Host**: `HOST_NAME`, `HOST_DOMAIN`, `HOST_IP`, `HOST_NUMBER`, `NET_DEVICE`.
  Set `STANDALONE=yes` for a single host without an uplink bridge.
- **Passwords**: change `ADMIN_PASSWORD`, `AUTH_DB_PASSWORD`,
  `DAAS_DB_PASSWORD`, `PVE_API_PASSWORD` (every `change-me-*` value). `ADMIN_EMAIL` /
  `ADMIN_PASSWORD` is the first admin account you log in with.
- **Public URLs**: leave `DAAS_PUBLIC_URL`, `FRONTEND_PUBLIC_URL` and
  `AUTH_PUBLIC_URL` empty; then everything runs under `HOST_NAME.HOST_DOMAIN`.
  Set them only for other names (DNS alias, reverse proxy); the rules are in
  the comment above them. `AUTH_PUBLIC_URL` must stay `FRONTEND_PUBLIC_URL/auth`.
- Optional: mail settings.

Each key is explained in the file itself.

### 2. Install everything

```bash
make install
```

On a fresh Debian this **stops after the first step** with
`Reboot into the PVE kernel, then run this again`. Then:

```bash
reboot
cd /daas/design-daas/installer && make install
```

The second run skips what is already done and goes through all seven steps.
Each step prints a banner like `==== [4/7] Docker images ====`:

| Step | make target | What it does |
|---|---|---|
| 1/7 | `proxmox-install` | Proxmox repo + PVE kernel (then **reboot**), then `proxmox-ve`. Skipped when Proxmox is already installed. |
| 2/7 | `deps` | **All host dependencies** in one place: docker, nginx, dnsmasq, Python build tools, ISO tools, git, jq, ...; docker data root `/home/daas-docker`; `docker-compose`; an SSH key for root (`/root/.ssh/id_rsa`). |
| 3/7 | `daas-install` `daas-configure` | Python venv + `daas.service` (not started yet); writes the host values and passwords from `daas.env` to `src/config/local/*.toml`, the nginx site, the TLS certificate and dnsmasq (DHCP for the instances). |
| 4/7 | `images` | Builds the service containers (`containers-install`) and the desktop images (`images-install`). |
| 5/7 | `auth-install` | Builds and starts the auth service; creates the admin account on its first start and checks the login. |
| 6/7 | `frontend-all` `daas-restart` | nginx site :8443, builds and starts the frontend, then starts the DaaS backend (which starts the containers and creates the Proxmox storages and bridges). |
| 7/7 | `iso-install` | Builds the three ISOs (Debian 12, Windows 10, Windows 11; Windows downloads about 11 GB from Microsoft once) and uploads them to Proxmox. Takes long the first time; `make install SKIP_ISOS=1` skips it, `make iso-install` runs it later |

Every step is safe to run again, so after an error: fix the cause and run
`make install` again (or just the failed step's target).

### 3. Check it

```bash
make status
```

One line per component. Everything should be `active` / `running` /
`installed` / `built` (the ISOs). If not, see [Troubleshooting](#troubleshooting).

## Using it

Steps 7 and 8 of the [top-level README](../README.md#7-prepare-the-computer-with-the-browser)
describe it exactly; in short:

1. On the computer with the browser, add the line `make client-hosts` prints
   to `/etc/hosts` (unless DNS resolves the names).
2. Import `/etc/nginx/ssl/daas-ca.crt` from the host into the browser as a
   trusted authority (required, otherwise the frontend cannot reach the
   backend in the background).
3. Open `https://<host>:8443/` and log in with `ADMIN_EMAIL` / `ADMIN_PASSWORD`.

Using other names than `HOST_NAME.HOST_DOMAIN`, e.g. the test names
`pve.cluster.local` / `front0.cluster.local`: `./use-hostnames.bash [<ip>]`
sets the three public URLs in `daas.env` and re-runs the steps that use them.
`HOST_NAME` / `HOST_DOMAIN` stay as they are: `HOST_NAME` is also the Proxmox
node name and must not change after the install.

## Everyday commands

| Command | What it does |
|---|---|
| `make status` | State of every component, one line each |
| `make start` / `stop` / `restart` | The three services auth, daas, frontend (daas starts/stops the containers) |
| `make logs` | Follow the logs of auth, daas and frontend |
| `make configure` | You changed `daas.env`: apply it without rebuilding |
| `make client-hosts` | The hosts file line for the computers with a browser (all names of the public URLs) |
| `make reinstall` | You changed code: rebuild the services, containers and images (data is kept) |
| `make delete` | Remove services, containers and images (data is kept) |
| `make backup` | Save all data to `backups/<time>/` (see [Backup and restore](#backup-and-restore)) |
| `make <command> PURGE=1` | `delete` / `reinstall` also delete the data (auth DB + keys, `src/data`, nginx sites, the DaaS PostgreSQL) |

**`PURGE=1` and `make reset` delete data for good**, including
`src/data/db/postgres`, the whole database of the DaaS backend and the auth
service. Run `make backup` first.

Frontend URLs and auth service settings are baked into their builds, so after
changing those in `daas.env` run `make frontend-install` / `make auth-install`
instead of `make configure`.

## Backup and restore

You only need this before deleting data (`make reset`, `PURGE=1`). Installing,
`make reinstall` and restarts keep all data.

```bash
make backup
```

saves everything into one folder `backups/<time>/` (root only, not in git),
while the system runs:

| File | Content |
|---|---|
| `postgres.sql.gz` | The whole PostgreSQL: the DaaS backend's database `mergedb`, the auth service's database (users, groups, permissions) and their roles |
| `auth-keys.tar.gz` | The auth service's token signing key (`rsa-jwk.json`); without it every issued token becomes invalid |

Restore (replaces the current data; `<time>` is the backup folder):

```bash
cd /daas/design-daas/installer
make stop                                   # auth, backend and frontend; the backend also stops the containers
make db-start
gzip -dc backups/<time>/postgres.sql.gz | docker exec -i daas-0-postgres psql -U postgres -q
docker run --rm --entrypoint tar -v daas-auth_keys:/app/keys -v "$PWD/backups/<time>":/b:ro \
    daas-auth -xzf /b/auth-keys.tar.gz -C /app/keys
make start
make daas-check auth-check
```

The restore prints two expected errors about the role `postgres`
(`current user cannot be dropped`, `role "postgres" already exists`); there
must be no others.

### One component

`make <component>-<action>`, for example `make db-logs`,
`make frontend-restart`, `make extensions-reinstall`:

| Kind | Components | Actions |
|---|---|---|
| service | `auth` `daas` `frontend` | install start stop restart status logs delete reinstall |
| container | `guacd` `rabbit` `db` `extensions` | install start stop restart status logs delete reinstall |
| image | `x11vnc` `wine` | install status delete reinstall |
| host | `nginx` `dnsmasq` `docker` `proxmox` | start stop restart status logs |
| iso | `iso` | install status delete reinstall |

Groups: `make containers-install`, `make images-install`, `make images`
(both), `make images-delete`. The old names `daas-services` /
`daas-containers` still work.

### Multi-host / Ceph (experimental)

**Experimental:** not tested with the current version of the system, and not needed for a single host. `make install` does not use it.

`proxmox-install-ceph`, `proxmox-install-ceph-osd` (`CEPH_DISK=/dev/vdb`),
`proxmox-install-ceph-cephfs`, `proxmox-install-ceph-pool`,
`proxmox-cluster-create` / `proxmox-cluster-join` (both need `LINK_IP=...`).

## Changing passwords

The passwords live in `daas.env` (root only, not in git). The DaaS
backend gets them through `src/config/local/` (also not in git), which
`make daas-configure` writes. Never put a password into a tracked file:
this repository is public.

| Password | Change it in `daas.env`, then |
|---|---|
| `PVE_API_PASSWORD` (Proxmox account `daas@pve` of the backend) | `make daas-configure daas-restart` (configure sets it in Proxmox) |
| `ADMIN_PASSWORD` (admin of the auth service, also used by the backend) | `make auth-admin-password daas-configure daas-restart` |
| `DAAS_DB_PASSWORD` (superuser of the stack's PostgreSQL) | see `postgres/README.md` (only applied to a new data folder) |

Generate one with `head -c 48 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32`.

## Which files do I edit?

Only **`daas.env`**. Every other settings file is written from it by the
installer and overwritten on its next run:

| File | Written by | Edit? |
|---|---|---|
| `daas.env.example` | in git: the template `make env` copies | no |
| **`daas.env`** | you (`make env` creates it) | **yes, the only one** |
| `auth/.env`, `frontend/.env` | `auth-install`, `frontend-install` | no (`Do not edit` in their header) |
| `../src/config/local/*.toml` | `daas-configure`: host values and passwords for the DaaS backend | no |
| `../src/config/*.toml` | in git: the DaaS backend's defaults | only when developing the backend |

After changing `daas.env`, apply it:

| You changed | Run |
|---|---|
| host values, `NET_DEVICE`, `DAAS_AUTH_*` | `make configure` |
| `AUTH_*` (except passwords), `MAIL_*`, `OAUTH_*` | `make auth-install`, and for `OAUTH_CLIENT_ID` also `make frontend-install configure` |
| the public URLs | the commands in the comment above them in `daas.env` |
| a password | see [Changing passwords](#changing-passwords) |

## Configuration

Values come from, in this order: the command line
(`make install HOST_NUMBER=12`), the environment, `daas.env`, the default.
`make help` shows the values in use.

## Troubleshooting

- **Full log**: every step appends to `/var/log/daas-installer.log`.
  Use `DAAS_DEBUG=1 make <target>` for verbose output with shell tracing,
  `DAAS_LOG_FILE=` to log to the console only.
- **`Required command not found: ... (make deps)`**: a step ran before the
  dependencies; run `make deps`.
- **`Not running a PVE kernel yet`**: reboot after the first
  `make install` / `make proxmox-install`.
- **`Missing .../daas.env`**: run `make env` and edit it.
- **A service does not start**: `make <service>-logs`, e.g. `make auth-logs`.
- **dnsmasq is not running** right after `daas-configure`: expected, it needs
  the `vmbr1` bridge, which the DaaS backend creates on its first start.

## Folder layout

| Path | Content |
|---|---|
| `Makefile` | All targets (this page) |
| `service.bash` | start/stop/status/logs/delete of every component (called by the Makefile) |
| `daas.env.example` | Settings template, copied to `daas.env` by `make env` |
| `use-hostnames.bash` | Switch to the `*.cluster.local` test names |
| `lib/` | Shared shell helpers (logging, checks) |
| `proxmox/` | Proxmox install, Ceph, cluster, ISO upload |
| `deps/` | Host dependencies (`make deps`) |
| `daas/` | DaaS backend: install, configure, nginx site, certificate |
| `auth/`, `frontend/` | docker-compose setup of the auth service and the frontend |
| `guacd/`, `rabbit/`, `postgres/`, `extensions/` | Service container images |
| `x11vnc/`, `wine/` | Desktop images |
| `iso/` | ISO generator (see `iso/README.md`) |
