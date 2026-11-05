# daas: the DaaS backend on the host

Installs and configures the **DaaS backend** (`src/main.py`, this
repository) as `daas.service`, plus the host pieces around it: nginx, the
TLS certificate and dnsmasq. The backend creates and controls the VMs and
containers, starts the service containers (guacd, rabbit, db, extensions)
and serves the API and the desktop viewer.

```
browser ─https :443─ nginx (daas.conf) ─https─ backend 127.0.0.1:5000 (daas.service)
                                                 ├─ Proxmox API 127.0.0.1:8006 (VMs, bridges, storages)
                                                 ├─ docker: service containers + container instances
                                                 └─ auth service 127.0.0.1:AUTH_PORT (login check)
VMs on vmbr1 ─ DHCP from dnsmasq (fixed address per VM, written by the backend)
```

## Commands

From `installer/`, as root:

| Command | What it does |
|---|---|
| `make daas-install` | Python venv + backend TLS key (`src/Makefile install`, only if there is no venv yet) and the `daas.service` unit. Starts nothing |
| `make daas-configure` | `daas.env` → `src/config/*.toml`, certificate, nginx (reload only), dnsmasq, `src/data` |
| `make daas-start` / `daas-stop` / `daas-restart` | The backend; it starts/stops the service containers itself |
| `make daas-status` / `daas-logs` | State / follow the log (`journalctl -u daas -f`) |
| `make daas-check` | Tests the running backend (changes nothing): service and its process, public address through nginx with a valid certificate, backend reachable only through nginx, the 4 service containers, TLS 1.2/1.3 only, nginx restarts cannot stop the backend |
| `make daas-reinstall` | Delete + install (fresh venv) + configure + restart, after code or dependency changes |
| `make daas-delete [PURGE=1]` | Removes the unit and the venv (`PURGE=1`: also `src/data` and the nginx site) |

A restart stops and starts the service containers: open desktop sessions
drop for ~10 seconds. `daas-configure` and `frontend-configure` do **not**
restart the backend (nginx is only reloaded).

## What `daas-configure` writes

| Target | From |
|---|---|
| `src/config/qweb.toml` | listen `127.0.0.1:5000`; public address (`hostproto/hostip/hostport`) from `DAAS_PUBLIC_URL` |
| `src/config/proxy.toml` | viewer address from `DAAS_PUBLIC_URL` |
| `src/config/vm.toml` | node `HOST_NAME`, bridge addresses `192.168.{123,223,100,200}.HOST_NUMBER`, uplink `NET_DEVICE` (not with `STANDALONE`) |
| `src/config/container.toml` | host address for the containers |
| `src/config/auth.toml` | login through the auth service (`DAAS_AUTH_MODE`, `ADMIN_EMAIL`, `OAUTH_CLIENT_ID`) |
| Proxmox user `daas@pve` | created with the Administrator role when missing; its password is set to `PVE_API_PASSWORD` when that does not log in |
| `src/config/local/vm.toml`, `local/auth.toml` | **the secrets** (`PVE_API_PASSWORD`, `ADMIN_PASSWORD`), root-only and not in git; the backend merges them over the tracked files (see `src/config/README.md`) |
| `/etc/nginx/ssl/` | local CA `daas-ca.crt` (once) + certificate for every public name (`DAAS_PUBLIC_URL`, `FRONTEND_PUBLIC_URL`, `AUTH_PUBLIC_URL`), see `mkcert.bash` |
| `/etc/nginx/nginx.conf`, `sites-enabled/daas.conf` | from `nginx.conf` / `daas.conf` here; server name = host of `DAAS_PUBLIC_URL` |
| `/etc/dnsmasq.conf` | DHCP on vmbr1 (`.50`–`.75`), gateway `192.168.223.HOST_NUMBER` |
| `/etc/dnsmasq.d/pve-hosts.conf` | **only created when missing**: the backend adds a fixed address per VM there |
| `src/data` | copied from `src/data_template`, existing files are kept |

Run it again after changing `daas.env`; every value is set by key, so it
can be repeated with other values.

## How the service runs

- `start.bash` runs `src/.venv/bin/python3 main.py` (with the venv's
  `PATH`) as the service's main process; output goes to the journal.
- Stop: systemd sends SIGTERM to the backend only (`KillMode=mixed`); it
  stops its service containers and exits, anything left after 60 s is
  killed.
- `Restart=on-failure`. Depends on docker (`Requires`); nginx, Proxmox
  and the auth service are only ordered before it (`Wants`), so restarting
  them never restarts the backend.

## Files

| File | Content |
|---|---|
| `install.bash` | venv + `daas.service` |
| `configure.bash` | Everything in the table above |
| `start.bash` | `ExecStart` of `daas.service` |
| `delete.bash` | Removes the unit and the venv (`-p`: data, nginx site) |
| `mkcert.bash` | Local CA + server certificate |
| `nginx.conf`, `daas.conf` | nginx main config and the DaaS site |
| `check.bash` | The test behind `make daas-check` |

## Things to know

- Import `/etc/nginx/ssl/daas-ca.crt` into the browser once; the
  certificate is renewed automatically when names change or it expires
  within 30 days (on the next `daas-configure`).
- `src/config/qweb.toml` has `debug = true`; consider turning it off for
  production.
- During development the backend can also run by hand
  (`cd src && make local-start`); stop `daas.service` first.
