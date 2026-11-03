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

## Values set by the installer

`installer/daas/configure.bash` (`make daas-configure`) sets these keys by
name, so manual edits to them are overwritten on the next run:

| File | Key | Value |
|---|---|---|
| `qweb.toml` | `hostip` | `HOST_NAME.HOST_DOMAIN` |
| `proxy.toml` | `viewer_host` | `HOST_NAME.HOST_DOMAIN` |
| `vm.toml` | `node` | `HOST_NAME` |
| `vm.toml` | `hostIp` | `192.168.123.HOST_NUMBER` |
| `vm.toml` | `bridge_cidr_{daas,inst,ceph,cluster}` | `192.168.{123,223,100,200}.HOST_NUMBER/24` |
| `vm.toml` | `bridge_gw_daas`, `bridge_adapter_daas` | `192.168.123.1` / `NET_DEVICE`, empty when `STANDALONE` |
| `container.toml` | `host` | `192.168.123.HOST_NUMBER` |

## Secrets

These files are in git and hold prototype credentials: Proxmox
`vm.toml apipass`, MariaDB `db.toml db_pass` (must match
`installer/mariadb/Dockerfile`) and the remote auth account in
`auth.toml [auth.remote]`. Change them for any real deployment.
