# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [2.0.0]

## [1.0.0]

Branch `new-version` compared with `master`: 104 commits, about 500 files changed 
(+8.7k / -31k lines, without `node_modules`).

### Breaking changes

- **New installer workflow.** The many separate `make` targets with exported 
  `HOST_*` variables are replaced by `make env` → `make install` (→ reboot → 
  `make install`) → `make status`. Settings now live in one file, 
  `installer/daas.env` (template: `installer/daas.env.example`).
- **Secrets moved out of git.** Passwords in `src/config/*.toml` are now empty 
  placeholders. The installer writes the real values to `src/config/local/*.toml`
  (git-ignored, root only), which is merged over the tracked files at startup  
  (`app/qweb/common/tomlfile.py`).
- **Every config key is now required, unused keys were removed.** Each TOML
  section is passed as `Dataclass(**section)`, so an old config file with
  extra or missing keys stops the plugin from loading. Removed keys include
  `db.database`, `db.admin_credentials`, `samples.*_owner_name` and
  `samples.persist_*`.
- **Changed defaults** in `src/config`:
  - `auth.toml`: `authenticator_type` `local` → `remote`,
    `enable_auth_endpoint` `true` → `false`, remote URL now
    `http://127.0.0.1:8080` (local auth service).
  - `db.toml`: `db_type` `sqlite` → `mariadb` (container `daas-0-mariadb`).
  - `qweb.toml`: `enable_testing` and `debug` → `false`,
    `host` `0.0.0.0` → `127.0.0.1` (only nginx reaches the backend).
- **Routes are declared as data.** The `inspect.currentframe()` stub
  functions and `handle_frame()` are gone; each route is registered with
  `name`, `url` and `description`, and handled by `handle_request(name)`.
  `BlueprintHandler` no longer takes `testing` / `default_handler`.
- **Removed components** (see [Removed](#removed)): the old extensions
  `Backend/` and `webapp/`, `src/Dockerfile`, `src/app/inst/cmdline.py`,
  the test/plot scripts in `src/scripts/`.

### Added

- **Installer**
  - `installer/README.md`: full step-by-step install guide, everyday
    commands, password handling, troubleshooting.
  - `installer/daas.env.example`, `make env`, `make install` (7 numbered,
    re-runnable steps, `SKIP_ISOS=1` to skip the ISOs).
  - `installer/service.bash` and lifecycle targets for every component:
    `make <component>-{install,start,stop,restart,status,logs,delete,reinstall}`
    plus `make status|start|stop|restart|logs|configure|reinstall|delete`
    and `PURGE=1` to also delete data.
  - `installer/deps/`: all host dependencies in one step (`make deps`).
  - `installer/auth/`: installs the Java auth service
    (`design-daas-backend-java`) with its own MariaDB via docker-compose,
    plus `backup.bash` and `set-admin-password.bash`.
  - `installer/frontend/docker-compose.yml`: frontend now runs in a
    container (`daas-frontend`) behind nginx :8443.
  - `installer/lib/common.bash`: shared logging/check helpers; every step
    logs to `/var/log/daas-installer.log`, `DAAS_DEBUG=1` for tracing.
  - `check.bash` and `README.md` for every component (auth, daas, deps,
    extensions, frontend, guacd, iso, mariadb, proxmox, rabbit, wine, x11vnc).
  - `installer/daas/delete.bash`, `installer/frontend/delete.bash`,
    `installer/proxmox/isoupload.bash`, `installer/use-hostnames.bash`.
  - `installer/daas/migrate-sqlite-to-mariadb.py`: one-time copy of the old
    SQLite database into MariaDB.
  - `.dockerignore` files for all images.
- **Backend**
  - `src/config/README.md`: what every config file is for, which keys the
    installer sets, and what to change for production.
  - Comments on every key in `src/config/*.toml`; new `node.toml` and
    `proxy.toml` entries.
  - Role checks on routes: `admin_only` (admin and limits routes) and
    `protect_system_objects` (only admins may change or delete system
    objects such as templates; answers `403`).
  - Each route now has a `description`.
  - MariaDB connect retries (30 × 2 s) at startup.
  - Printer setup after an instance boots (per-owner queue on the print
    service, then the printer in the instance; Windows aware).
  - Progress log every minute while waiting for an instance to boot.
  - Resource limit check skips objects that are already running.
- **Desktop images / ISOs**
  - guacd built from guacamole-server **1.6.0**.
  - `wine` image: Debian trixie, Wine 10, ready Wine prefix with core fonts.
  - `installer/iso/scripts/generate-windows-iso.bash`: one script for
    Windows 10 and 11.

### Changed

- **RabbitMQ messaging** (agent ↔ backend) reworked for stability:
  - RPC sender keeps one connection and one reply queue, reconnects once
    on a dropped connection (only the publish is retried, so a command is
    never run twice), and logs short request / answer / exit-code lines.
  - RPC receiver and heartbeat sender own their connection in one thread
    (pika is not thread-safe), process one request at a time
    (`prefetch_count=1`) and stop cleanly via a stop event.
  - Fixes the agent reconnect loop.
- **Proxmox API**: qemu `args` are set with `qm set` as root (the API user
  may not set them); VM delete waits for the destroy task; objects already
  removed in Proxmox are cleaned up from the database.
- **Remote auth**: user role is read from the auth service; endpoint
  permission checks are skipped when `enable_auth_endpoint` is off;
  removed unused permission lookups.
- **Config loading** goes through `read_toml_with_local()` everywhere.
- **Extensions container** (`VNCService/`): reduced to printing only
  (CUPS + cups-pdf on :631, Node.js 24 `server.js` on :8010). The
  microphone now goes straight from the backend to the instance (`pacat`).
- **x11vnc / wine images**: rewritten Dockerfiles, entrypoints and
  Makefiles; VNC password and pulse configs no longer committed as files.
- **nginx / TLS**: reworked `installer/daas/nginx.conf` and `mkcert.bash`
  (local CA at `/etc/nginx/ssl/daas-ca.crt`).
- **Proxmox install** (`install.bash`, `ceph.bash`, `cluster.bash`)
  rewritten to be idempotent; Ceph version selectable (`CEPH_VERSION`,
  default `reef`).
- **ISOs**: updated Windows `autounattend.xml` and Debian postinstall;
  ISO Makefile rewritten.
- Root `README.md`: install section now points to `installer/README.md`;
  usage uses `make -C installer status|restart|logs`.
- `.gitignore`: ignores `daas.env`, `.env` files, `src/config/local/`,
  `*.bak-*` backups, the local CA and `.idea/`.
- Old documentation and screenshots moved to `archiv/`.

### Removed

- `installer/extensions/Backend/` and `installer/extensions/webapp/`
  (old Node backend and React test app for audio/print).
- Audio servers/clients in `VNCService/`.
- `installer/iso/playground/`, `generate-win10-iso.bash`,
  `generate-win11-iso.bash` (replaced by `generate-windows-iso.bash`).
- `installer/guacd/guacamole-server-1.5.4.tar.gz`,
  `installer/guacd/entrypoint.bash`, `installer/rabbit/run.bash`,
  `installer/proxmox/configure.bash`, `installer/daas/stop.bash`,
  `installer/frontend/start.bash` / `stop.bash` (replaced by
  `service.bash`).
- `.gitmodules` (guacamole-client submodule).
- `src/Dockerfile`, `src/README.md`, `src/scripts/` (plot and curl/browser
  test scripts) and the `nest_asyncio`, `pandas`, `matplotlib`
  dependencies.
- `src/app/inst/cmdline.py`, `push2ip.bash`, `push2x11cont.bash`,
  `timings.py`.
- Dead backend code: `daas/messaging/runner_backend.py`,
  `runner_local.py`, `storage/ceph/ceph_actions.py`,
  `ceph_permissions.py`, `objects/config_factory.py`,
  `resources/info/sysinfo.py`, `qweb/service/service_tasks.py` task
  helpers, unused config/enum/model classes, local password-hash storage.
- Unused static files in `src/app/webroot/static/` (status images,
  `viewer_layout_old.js`, `viewer-styles.css`, `my-processor.js`).

### Security

- Real account credentials removed from `src/config/auth.toml` and the
  MariaDB password from `db.toml`.
- Test routes (`/testing`, `/baseline0`..`6`) disabled by default.
- Backend listens on `127.0.0.1` only.
- Still open for production (see `src/config/README.md`):
  `qweb.toml allow_origin = "*"` and `db.toml include_samples = true`.
