# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [2.0.0]

Review and cleanup of the backend (`src/app`, the DaaS engine). API routes,
config keys and the database schema are unchanged. The second review pass
checked the backend against the frontend (`design-daas-application-frontend`)
and the auth service (`design-daas-backend-java`).

### Fixed

- **Fresh install had no admin account**: the installer runs the auth service
  with the `prod` profile, which only creates the bootstrap admin when
  `ADMIN_INIT_ENABLED=true`, but `installer/auth/docker-compose.yml` never
  set it. It now does; the auth service skips it once the admin exists.
- **Expired tokens were never refreshed on DaaS calls**: a failed login check
  answered `403`, but the frontend only refreshes its token on `401`. Failed
  authentication now answers `401`; ownership and system-object denials stay
  `403`.
- **`bearer` in a JSON body was ignored**: `_extract_bearer` found the key
  in the JSON body but then read it from the form, which has no such key for
  JSON requests, so the request failed with a `KeyError`. It now reads it
  from the JSON body.
- **Admin monitoring always empty**: `/admin/get_monitor_info_*` passed
  `id_owner` on as a string (`""` for all users, `"5"` for one user), but the
  monitoring code compares with the int `0` (all) and int owner ids, so
  nothing matched. `id_owner` is now parsed to an int (empty = all users);
  `/admin/tasklist`, `/admin/taskstop` and the `owner` of
  `/admin/assign_obj_to_user` / `/admin/assign_app` too.
- **`/vm/start` created instances for user `-1`**: the route ran its task in
  `AUTH_AND_PROC` mode, i.e. in parallel with authentication and with an
  empty user, so the instance owner and the resource limit check used `-1`.
  It now authenticates first (`CTX_AND_AUTH`).
- **Unchecked checkboxes counted as checked**: the frontend sends an
  unchecked box as `''`, but `connect`, `force` and `detailed` were tested
  with `"x" in reqargs`, so e.g. an unchecked "connect" still connected and
  every environment stop was forced. All flags are now
  `reqargs.get(x, "") != ""`.
- **Optional arguments read with `reqargs[x]`** (`force` of
  `/phases/baseimage_stop`, `execute` of `/inst/vminvoke_upload`, `id_object`
  / `id_instance` of the admin task routes): a request without them failed
  with a `KeyError` (500). They default to `""` now.
- **Auth service adapter** (`daas/auth/auth_daas_remote.py`):
  - When the auth service did not answer, logging the error crashed
    (`None.status`).
  - With `enable_auth_endpoint` on, the endpoint check dropped the user's
    role, so admins lost access to admin routes.
  - Viewer tokens logged "success" also for unknown tokens, and the token
    itself was stored as the user name (and so ended up in logs).
- **HTTP status codes**: a requested object that does not exist now answers
  `404 "<Type> '<name>' not found"` (new `ObjectNotFoundError`) instead of a
  500 with a traceback; an ownership failure answers `403` instead of `500`;
  a failed authentication in `AUTH_AND_PROC` mode answers `403
  Authentication error` instead of `500 Procargs not created ...`.
- **Guacamole tunnel** (`daas/proxy/guacamole_proxy.py`):
  - Closed connections stayed in the global `socket_tuples` map for good
    (memory leak), and the socket to guacd was never closed. Both sides are
    now always cleaned up in one `finally`, whichever side closes first,
    including unexpected errors that used to leave the other task running.
  - The stats counted client messages as guacd messages and the other way
    round, counted every client message as a blob, added client bytes twice,
    and never counted guacd blobs. Counting is now one shared helper; the
    rates no longer divide by zero.
  - The idle timeout check compared against the wrong side's timestamp and
    did nothing (its `raise` was commented out); removed.
- **Microphone proxy**: the `pacat` process was not stopped when the browser
  disconnected, and the loop spun the CPU while the pipe was not ready. The
  process is now always terminated and the connection deregistered.
- **Printer proxy**: when one direction ended, the other kept running forever.
  The tunnel now ends when either side closes; it closed the browser socket
  with the invalid code 512 (now 1000) and did not deregister the connection.
- **Node routes** (`/node/vmconfigure_dhcp`, `/node/vmconfigure_iptables`)
  always failed: wrong task signature and missing `await`. `/node/vminvoke_upload`
  answers `501` instead of raising.
- **Instance routes** `/inst/vminvoke_filesystem` and `/inst/vminvoke_rtt`
  called methods with wrong arguments that only raised `NotImplementedError`;
  they now answer `501 not implemented`.
- **Test route** `TEST_GET_ENTITY` had the wrong task signature.
- **Task launch**: `run_apitask` / `run_system_task` checked `task != ""`
  although a missing task is `None`, so an unknown task name crashed.
- **Task errors**: the error handler itself crashed (`exe.args[0]`) on
  exceptions without arguments; the traceback is now logged.
- **Container installers** were uploaded twice into the instance.
- **Clone**: the new object kept the old object's id until `clone()` ran, so
  the resource limit check was skipped when the source object was running.
- **Host info**: `du` / `df` ran synchronously inside async code and froze the
  whole backend while `du` walked large folders; they now run as async
  subprocesses.
- Error messages of `baseimage_create_from_app` / `baseimage_clone_from_app`
  said "Clone object failed" for different errors.
- 22 mutable default arguments (`args: dict = {}`, `files: list = []`)
  replaced by `None`.

### Removed

- `plugins/platform/vm/vm_tasks_sys.py`: system task `VM_CONFIGURE_PROXMOX_VNC`
  that was never started and ended in an endless `while True` loop.
- Commented-out code: the old SQLite schema and access-token functions in
  `db/database.py`, the commented abstract methods in `common/model.py`, the
  commented `run_systask` in `qweb/common/qweb_tools.py`.
- Unused code: `AuthDatabase`, `_execute_sql_insert` and the `aiosqlite`
  import, `AccessToken`, `DEFAULT_ADMIN_ID`, empty sample factories
  (`create_demo_instances/connection/environments`), `WebsocketStats.tostring`,
  `GuacamoleSocket.get_path`, `inst_vmstatus` / `inst_vmversion`,
  `FilestoreInstances.upload_file_to_instance` and its private upload helper,
  unused command constants, `DEFAULT_VM_OS`, `DEFAULT_CNT_DISKSIZE_LINUX`,
  the unused `timeout` / `logme` / `win` parameters, useless `__init__`
  overrides and a debug `print(sys.path)` in the instance agent.

### Changed

- **Logs**:
  - Docker start/stop errors name the service or container
    ("Starting service daas-0-guacd failed: ...") instead of
    "Exception raised1", and include the traceback in debug mode.
  - dhcp / iptables setup logs success or the error, not always "configured".
  - Guacamole, audio and printer connections log which side closed and why,
    with the connection id.
  - Sample import logs every imported object, file, limit and application.
- `TableEntityMapping` simplified (no `None` checks, `dict.get`).
- `check_data` explains why it reads `orm.app` / `orm.env` (loads the lazy
  relationships).
- Default resources in `phases_tasks.py` documented (memory MiB, disk bytes);
  `DEFAULT_CNT_DISKSIZE_WIN` renamed to `DEFAULT_CNT_DISKSIZE` (used for all
  containers). Values unchanged.
- `pyproject.toml`: black `line-length` 80 → 88, which is what the code is
  formatted with.

### Not changed (noted for later)

- **Frontend ↔ backend mismatches**: fixed in the frontend, version 2.2.1
  (environment stop sent the instance id instead of the object id; three
  admin actions called endpoints that do not exist; `viewer_resize` /
  `viewer_scale` values the backend does not accept). See the frontend's
  `CHANGELOG.md`.
- **`AUTH_AND_PROC` mode** (33 routes, e.g. `/vm/stop`, `/vm/status`, the
  viewer and websocket routes) still runs the task before authentication
  and the ownership check have finished. The checks happen afterwards, so a
  request with a bad token or for another user's VM has already done its
  work by the time it is answered with 403.
- The backend ↔ auth service contract matches: `/oauth2/user/token` (form),
  `/oauth2/user/session` (`user_id`, `name`, `role`) and
  `/permissions/{function}/{userId}` (`result`, `user.id`, `user.name`).

- `websockets.WebSocketClientProtocol` is deprecated in websockets 17; the
  type hints still use it.
- Many broad `except Exception` blocks remain; they log the error now.

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
