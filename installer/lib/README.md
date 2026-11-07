# lib: shared helpers of the installer scripts

Not run directly. Every installer script starts with

```bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.bash"
```

## common.bash

**Behaviour it switches on**

- `set -Eeuo pipefail`: stop on the first error, unset variable or
  failing pipe; the error trap reports the failing command, line and
  exit code.
- Logging: every message goes to the console and is appended to
  `/var/log/daas-installer.log` (`DAAS_LOG_FILE=<path>` for another file,
  `DAAS_LOG_FILE=` for none). Normal users (e.g. `make status`) log to the
  console only. `DAAS_DEBUG=1` adds debug messages and shell tracing.
- `DEBIAN_FRONTEND=noninteractive` for apt.

**Helpers**

| Helper | What it does |
|---|---|
| `info` `success` `warn` `error` `debug` `die` `step` | Log at that level (`die` also exits, `step` is a section header) |
| `run CMD...` | Log the command, run it, keep its output in the log |
| `require_root` `require_cmds` `require_dir` `require_file` | Stop early with a clear message (missing command: "run make deps") |
| `apt_install PKG...` | `apt-get install -y` |
| `write_file PATH [MODE]` | Write stdin to PATH (mode 644 or MODE) only if the content changed; logs "Wrote"/"Unchanged" and sets `WRITE_FILE_CHANGED`. The file has its final mode from the start, so a secret file is never readable by others |
| `set_toml_value FILE KEY VALUE [raw]` | Set `KEY = "VALUE"` (raw: `KEY = VALUE`) in a TOML file, whatever its old value; values of secret keys (`*pass*`, `*secret*`, `*token*`) are never logged |
| `load_env_file FILE` | Export `KEY=value` lines literally (no `$` expansion, quotes removed) |
| `load_stack_env FILE` | `load_env_file` for `installer/daas.env` plus the derived defaults (folders, public URLs, `FQDN`) and checks |
| `url_host URL`, `url_port URL` | Host / port of a URL (default port from the scheme) |
| `warn_default_secret NAME` | Stop if a secret is empty, warn if it still has its `change-me` example value |
| `write_compose_env FILE KEY...` | docker-compose env file (mode 600) from the current environment; checks all values first |
| `check_active UNIT` | Fail with the unit's last log lines unless it runs |
| `enable_and_restart UNIT...` | Enable, restart, check |
| `reload_nginx` | `nginx -t`, then reload (keeps connections, never restarts services that depend on nginx) or start |
| `wait_http URL [TRIES]` | Wait until URL answers at all (5 s per try) |
| `remove_unit NAME` | Stop, disable and delete a systemd unit |

## service_container.py

Prints the `docker run` arguments of one service container (guacd,
rabbit, db, extensions) from `src/config/container.toml`, exactly as the
DaaS backend starts it. `service.bash` uses it for
`make <container>-start`. Like the backend it understands `-p`, `-v` and
`--privileged`; other options are ignored with a warning.

```bash
python3 -I lib/service_container.py /root/design-daas daas-0-guacd
```

## Things to know

- `load_env_file` takes values literally: `KEY=value # note` makes
  `value # note` the value. Put comments on their own line.
- `WRITE_FILE_CHANGED` is not set when `write_file` is the last command
  of a pipe (it runs in a subshell there).
