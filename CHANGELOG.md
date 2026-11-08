# Changelog

All notable changes to this project are documented in this file. The project uses [Semantic
Versioning](https://semver.org/).

## [2.0.0]

- **Breaking — new installer:** `make env` → `make install` → `make status` replaces the old targets and `HOST_*`
  variables. All settings are in `installer/daas.env`; every component has `make <component>-{install,start,stop,
  restart,status,logs,delete,reinstall}`, a `check.bash` and a README, and logs go to `/var/log/daas-installer.log`.
- **Breaking — config:** passwords and host values are no longer in git. The installer writes them to
  `src/config/local/*.toml` (git-ignored), which is merged over the tracked files; tracked files are never edited.
  Every key is now required, unused keys were removed, and the SSH and MAC-prefix settings exist in one place only.
- **Breaking — defaults:** remote auth (Java service on `:8080`), MariaDB instead of SQLite, backend on `127.0.0.1`,
  `debug` and test routes off.
- **Breaking — routes are data:** each route has a `name`, `url` and `description` and is handled by
  `handle_request(name)`.
- Added the Java auth service install (own MariaDB, backup, admin password script) and the frontend as a container
  behind nginx.
- Added API docs generated from the routes: `GET /api/docs`, `/api/docs.json` and `make -C src api-docs`
  (`docs/api.md`).
- Added the `X-Request-ID` header: it is in every log line, in the response, and passed on to the auth service.
- Added `/monitoring/get_quota` (user limits vs. current usage) and `/monitoring/get_system_status` (admins: backend,
  auth service, service containers, frontend). `make status` also shows the auth service health.
- Added role checks (`admin_only`, `protect_system_objects`), MariaDB connect retries, printer setup in instances and a
  boot progress log.
- Updated guacd to 1.6.0, the wine image to Debian trixie / Wine 10, one Windows ISO script for 10 and 11, and
  rewrote the Proxmox, nginx/TLS and ISO setup to be re-runnable.
- Reworked RabbitMQ messaging: one connection per thread, reconnect without running a command twice, clean stop.
- Less duplicated code: create/clone tasks share one flow, VM and container objects share one API class, plugins no
  longer repeat their setup.
- Better logs: warnings vs. errors used correctly, real tracebacks, service and container names in errors, every
  closed connection logged with its reason, no `print()` in the instance agent.
- Python packages pinned to the tested versions.
- Fixed: routes that need a login ran their task before the login and owner check (e.g. `/vm/delete` with a bad token
  already deleted the VM, `/vm/start` created instances for user `-1`).
- Fixed: expired tokens were never refreshed (now `401` instead of `403`), and `bearer` in a JSON body was ignored.
- Fixed: admin monitoring and admin task routes found nothing because the owner id was a string.
- Fixed: unchecked checkboxes counted as checked, and missing optional arguments caused `500` errors.
- Fixed: missing objects answer `404`, ownership failures `403`, unimplemented routes `501` instead of `500`.
- Fixed: the Guacamole tunnel leaked closed connections and counted its stats wrong; the microphone and printer proxies
  did not stop when one side closed.
- Fixed: the auth adapter crashed when the auth service was down and dropped the admin role with endpoint checks on.
- Fixed: the instance agent died on an unknown request type, and its runner never stopped cleanly.
- Fixed: broken node and test routes, task launch and task error handling, installers uploaded twice, clone skipping
  the limit check, `du`/`df` blocking the backend, and 22 mutable default arguments.
- Removed the old extensions `Backend/` and `webapp/`, the audio servers, `src/Dockerfile`, the test and plot scripts,
  the SQLite migration script, the guacamole-client submodule and the old start/stop scripts.
- Removed dead and commented-out code, unused config keys, static files and the `pandas`, `matplotlib`,
  `nest_asyncio` and `mypy` dependencies.
- Removed real credentials from the config files.
