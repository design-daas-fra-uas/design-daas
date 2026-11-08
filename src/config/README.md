# Backend configuration (`src/config`)

One TOML file per plugin area. The backend reads them once at startup
(`main.py` → plugin `__init__`), so restart `daas.service` after a change.

**Every key is required.** Each section is passed as `Dataclass(**section)`,
so a missing or extra key stops the plugin from loading. To add or remove a
key, change the matching dataclass too (see the header of each file).

Relative paths are resolved against `src/` (the working directory of the
backend), except `logging.toml log_dir` and the docker `-v` volumes in
`container.toml`, which are relative to `src/data/`.

| File | Read by | Purpose |
|---|---|---|
| `qweb.toml` | runtime (`ConfigReader`) | HTTP server, TLS, CORS, folders |
| `logging.toml` | runtime (`LoggerConfig`) | log files and log targets |
| `auth.toml` | `AuthPlugin` | local (fixed user) or remote (OAuth) auth |
| `db.toml` | `DatabasePlugin` | sqlite / mariadb, sample data |
| `container.toml` | `ContainerPlugin` | Docker, service containers started by the backend |
| `vm.toml` | `VmPlugin` | Proxmox API, node, storages, network bridges |
| `node.toml` | `NodePlugin` | dnsmasq DHCP entries, local SSH |
| `messaging.toml` | `MessagingPlugin` / `InstancePlugin` | RabbitMQ + SSH to instances |
| `proxy.toml` | `ProxyPlugin` | guacd, viewer URL, reconnect timings |
| `extensions.toml` | `ExtensionsPlugin` | printing + microphone container |
| `files.toml` | `FilePlugin` | local folders, desktop image Dockerfiles |
| `ceph.toml` | `CephPlugin` | CephFS mounts (disabled by default) |
| `info.toml` | `InfoPlugin` | which VMs/images/containers count as DaaS |
| `limits.toml` | `LimitPlugin` | system-wide and per-user resource limits |

## Local overrides: `config/local/` (not in git)

Every file is read together with `config/local/<same name>.toml` when that
exists (`app/qweb/common/tomlfile.py`): its keys replace the ones here,
tables are merged key by key. The folder is ignored by git and readable
by root only.

The tracked files here hold **generic defaults** and empty password
placeholders. Everything that depends on the host, and every password, is
written to `config/local/` by `installer/daas/configure.bash`
(`make daas-configure`) from `installer/daas.env`. The installer never
edits the tracked files, so `git status` stays clean after an install.
Manual edits in `config/local/` are overwritten on the next
`make daas-configure`; change `installer/daas.env` instead.

| Override | Keys | From `installer/daas.env` |
|---|---|---|
| `local/qweb.toml` | `[template_args] hostproto`, `hostip`, `hostport` | scheme, host, port of `DAAS_PUBLIC_URL` |
| `local/proxy.toml` | `[viewer] viewer_protocol`, `viewer_host`, `viewer_port` | scheme, host, port of `DAAS_PUBLIC_URL` |
| `local/container.toml` | `[container_request] host` | `192.168.123.HOST_NUMBER` |
| `local/vm.toml` | `[vm_rest] apipass` | `PVE_API_PASSWORD` (Proxmox account `daas@pve`) |
| | `[vm_api] node`, `hostIp` | `HOST_NAME`, `192.168.123.HOST_NUMBER` |
| | `[vm_api] bridge_cidr_{daas,inst,ceph,cluster}` | `192.168.{123,223,100,200}.HOST_NUMBER/24` |
| | `[vm_api] bridge_gw_daas`, `bridge_adapter_daas` | `192.168.123.1` / `NET_DEVICE`, empty when `STANDALONE` |
| `local/db.toml` | `[db] db_pass` | `DAAS_DB_PASSWORD` (MariaDB root) |
| `local/auth.toml` | `[auth] authenticator_type`, `enable_auth_endpoint` | `DAAS_AUTH_MODE`, `DAAS_AUTH_CHECK_ENDPOINTS` |
| | `[auth.remote] url`, `clientid`, `scope`, `username`, `password` | `http://127.0.0.1:AUTH_PORT`, `OAUTH_CLIENT_ID`, `admin`, `ADMIN_EMAIL`, `ADMIN_PASSWORD` (remote mode only) |

Never put a password into a tracked file: this repository is public.

## Values to change for production

`enable_testing` and `debug` are `false`: the test routes (`/testing`, `/baseline0`..`6`,
some without login) are not loaded. Set it to `true` only on a test system.


| File | Key | Now | Why |
|---|---|---|---|
| `qweb.toml` | `allow_origin` | `"*"` | any web site may call the API from a browser |
| `db.toml` | `include_samples` | `true` | sample objects created on every start |

Keys that no code read were removed on 2026-11-06. Before adding a key here,
add the field to its dataclass and read it somewhere.
