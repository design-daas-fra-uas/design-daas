# Design DaaS installer

Everything here is driven by `make`. Run all commands **as root** from this
folder (`installer/`). `make help` prints a short version of this page.

## What you get

After `make install` one host runs the whole stack:

| Part | What it is | Where |
|---|---|---|
| Proxmox VE | Runs the VM instances (web UI for admins) | `https://<host>:8006` |
| DaaS backend | Python API that creates and controls the instances (`daas.service`) | `https://<host>` (nginx :443) |
| Frontend | React web app the users work in (`frontend.service`) | `https://<host>:8443` |
| auth service | Users, login (OAuth), permissions (`daas-auth.service`) + its own MariaDB | `https://<host>:8443/auth` |
| Service containers | `guacd`, `rabbit`, `db` (MariaDB: the DaaS backend's database), `extensions`; started and stopped by the DaaS backend | docker |
| Desktop images | `x11vnc`, `wine`; the DaaS backend starts one container per instance | docker |
| ISOs | Unattended install ISOs (win10, win11, debian12) in the `daas-iso` storage | Proxmox |

`<host>` is `HOST_NAME.HOST_DOMAIN` from `daas.env` (e.g. `pve1.daas-design.de`).

## What you need

- A fresh **Debian 12** machine (VM or bare metal) with internet access,
  root access and enough disk for the docker images and ISOs.
- The two other repositories cloned **next to this one** (or set their paths
  in `daas.env`):

  ```
  /root/design-daas                        this repo
  /root/design-daas-application-frontend   FRONTEND_FOLDER
  /root/design-daas-backend-java           AUTH_FOLDER
  ```
- `make`: `apt install make` if it is missing. Everything else is installed
  by the installer itself (step 2, `make deps`).

## Install, step by step

### 1. Create the settings file

```bash
cd /root/design-daas/installer
make env
```

This copies `daas.env.example` to `daas.env` (mode 600, not committed). Edit it:

- **Host**: `HOST_NAME`, `HOST_DOMAIN`, `HOST_IP`, `HOST_NUMBER`, `NET_DEVICE`.
  Set `STANDALONE=yes` for a single host without an uplink bridge.
- **Passwords**: change `ADMIN_PASSWORD`, `AUTH_DB_PASSWORD`,
  `AUTH_DB_ROOT_PASSWORD` (every `change-me-*` value). `ADMIN_EMAIL` /
  `ADMIN_PASSWORD` is the first admin account you log in with.
- Optional: other public URLs (DNS alias, reverse proxy), mail settings.

Each key is explained in the file itself.

### 2. Install everything

```bash
make install
```

On a fresh Debian this **stops after the first step** with
`Reboot into the PVE kernel, then run this again`. Then:

```bash
reboot
cd /root/design-daas/installer && make install
```

The second run skips what is already done and goes through all seven steps.
Each step prints a banner like `==== [4/7] Docker images ====`:

| Step | make target | What it does |
|---|---|---|
| 1/7 | `proxmox-install` | Proxmox repo + PVE kernel (then **reboot**), then `proxmox-ve`. Skipped when Proxmox is already installed. |
| 2/7 | `deps` | **All host dependencies** in one place: docker, nginx, dnsmasq, Python build tools, ISO tools, git, jq, ...; docker data root `/home/daas-docker`; `docker-compose`; an SSH key for root (`/root/.ssh/id_rsa`). |
| 3/7 | `daas-install` `daas-configure` | Python venv + `daas.service` (not started yet); writes `daas.env` into `src/config/*.toml`, the nginx site, the TLS certificate and dnsmasq (DHCP for the instances). |
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
`installed`. If not, see [Troubleshooting](#troubleshooting).

## Using it

1. On the computer with the browser, make `<host>` resolve to the host's IP
   (DNS, or a line in its hosts file).
2. Trust the local CA once: import `/etc/nginx/ssl/daas-ca.crt` from the host
   into the browser as a trusted authority. (Or accept the certificate
   warning on `https://<host>/` **and** `https://<host>:8443/`.)
3. Open `https://<host>:8443/` and log in with `ADMIN_EMAIL` / `ADMIN_PASSWORD`.

Using other names than `HOST_NAME.HOST_DOMAIN`, e.g. the test names
`pve.cluster.local` / `front0.cluster.local`: `./use-hostnames.bash [<ip>]`
sets them in `daas.env` and re-runs the steps that use them.

## Everyday commands

| Command | What it does |
|---|---|
| `make status` | State of every component, one line each |
| `make start` / `stop` / `restart` | The three services auth, daas, frontend (daas starts/stops the containers) |
| `make logs` | Follow the logs of auth, daas and frontend |
| `make configure` | You changed `daas.env`: apply it without rebuilding |
| `make reinstall` | You changed code: rebuild the services, containers and images (data is kept) |
| `make delete` | Remove services, containers and images (data is kept) |
| `make <command> PURGE=1` | `delete` / `reinstall` also delete the data (auth DB + keys, `src/data`, nginx sites, the DaaS MariaDB) |

**`PURGE=1` deletes data for good**, including `src/data/db/mariadb`, the
DaaS backend's whole database. Back it up first (`docker exec daas-0-mariadb
sh -c 'mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" mergedb' > daas.sql`)
and the auth service (`make auth-backup`).

Frontend URLs and auth service settings are baked into their builds, so after
changing those in `daas.env` run `make frontend-install` / `make auth-install`
instead of `make configure`.

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

### Multi-host / Ceph (optional)

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
| `DAAS_DB_PASSWORD` (DaaS backend's MariaDB) | see `mariadb/README.md` (only applied to a new data folder) |

Generate one with `head -c 48 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32`.

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
| `guacd/`, `rabbit/`, `mariadb/`, `extensions/` | Service container images |
| `x11vnc/`, `wine/` | Desktop images |
| `iso/` | ISO generator (see `iso/README.md`) |
