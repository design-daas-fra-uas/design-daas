# Code review of `src/app` (2026-11-05)

Scope: every tracked Python file under `src/app` (about 31,600 lines), except
`app/inst` (the agent that runs inside the VMs) where noted. Git-ignored files
were skipped.

Method: `pyflakes` and `pylint` (with the project's `.pylintrc`) to find
candidates, then each finding read by hand and checked against the running
system. Every change below was tested on the live installation: backend
restart, `make daas-check auth-check frontend-check`, and API calls as admin
(lists, dashboard, clone/start/delete of a VM and of a container).

The document has three parts:

1. **Already changed**: bugs fixed and cleanup done, without changing what the
   app is meant to do.
2. **Your decision**: places where I think the logic itself should change.
   Nothing here is changed yet.
3. **Dead code**: functions nothing calls, for you to keep or delete.

---

## 1. Already changed

### Bugs fixed

| Where | What was wrong | Effect before the fix |
|---|---|---|
| `daas/objects/phase_machine.py`, `phase_container.py` (4×) | `if k in args is False:` is a chained comparison, `(k in args) and (args is False)`, which is never true | The "required argument missing" checks never ran; a missing argument crashed later with a `KeyError` instead of a clear 400 |
| `phase_machine.py`, `plugins/platform/phases/phases_tasks.py` | `choose_template_root()` is a module function but was called as `self.choose_template_root()` / `entity.choose_template_root()` | **Creating a desktop from an app (install from ISO) crashed** with `AttributeError` (seen in the log on 2026-11-04 22:32) |
| `phases_tasks.py` `_create_empty_object_by_app` | `app.os_type in ("l26vm")` is a substring test on a string, not a tuple test, so `"l26"` matched it too | Container apps first built a VM object, then the crash above |
| `phases_tasks.py` `_create_empty_object` | `entity` was only assigned inside `if old is not None` | `UnboundLocalError` instead of a clean error when the source object is missing |
| 6 more places (`base_instance.py` 2×, `base_object.py`, `proxy_tasks.py`, `blueprint_handler.py`, `processor_api.py`) | Same `x in ("value")` pattern | Worked for normal values, but an **empty** value matched too (`"" in "run-app"` is `True`); now plain `==` |
| `daas/resources/info/infotools.py` | Called `to_json()`, the method is `tojson()` | `TaskCollection.tostring()` crashed |
| `daas/container/docker/DockerRequest.py` (2×) | `time.sleep()` inside `async` functions | Froze the **whole backend** (all users) while waiting for services at start and for every container stop; now `asyncio.sleep()` |
| `qweb/service/service_context.py` (3×) | `NotImplementedError()` built but not raised | No effect today (every backend implements the methods, checked), but now a missing method fails loudly |
| `daas/auth/auth_daas_remote.py`, `auth_daas_local.py` | User bearer tokens written to the log | Anyone who can read the journal could reuse a logged-in user's token |

One fix needed a follow-up: once the argument check really ran, it rejected
**container clone** requests, because its list contained `rootimage`. Container
clone never uses `rootimage`, and the frontend never sends it, so I removed it
from that list. All other required fields are always set by the callers (checked
against the routes and the frontend). `kb` and `os_type` for a new VM were
already read directly later on, so a request without them now gets a clear 400
instead of a crash.

### Cleanup (no behavior change)

- 27 unused imports and one duplicate import removed (20 files).
- 2 unused local variables removed (`inst_tasks.py`).
- 4 dead private helpers removed (`ObjectStats.__log_info`,
  `QwebTaskManager._remove_stopped_task`, `DatabaseApi._get_table_mapping_domain`,
  `Database._get_config_db`).

Left alone on purpose:
- `db_model.check_data`: its "unused" `getattr(orm, "app")` loads the
  relationship.
- `db_samples.py`: unused sample variables in commented-out demo data.
- Mutable defaults (`args: dict = {}`, 24×): none of them is ever changed, so
  they are harmless and match the code style.

---

## 2. Your decision: logic I think should change

Ordered by importance. Each item says what happens today, what I propose, and
what it costs.

### 2.1 Admin endpoints are open to every logged-in user (security, high): DONE

**Implemented 2026-11-05** as proposed below:
- `BlueprintInfo.admin_only` is set on all 13 `/admin/*` routes and on
  `/limits/put_limit`, `/limits/remove_limit` and `/limits/list_limits`.
  `/limits/get` stays open, since it only returns the caller's own limit.
- `blueprint_handler.task_authentication` treats a non-admin as unauthenticated
  on those routes, so they answer 403 and log "denied admin route".
- An `admin_only` route never runs processing in parallel with authentication.
- Admin routes skip the per-user ownership check. Before, the admin
  "limitation" page could not change another user's limit: that failed with
  500 "Invalid owner".

Tested with a throwaway normal user, deleted afterwards: 403 on every admin
route (with complete requests, and the limit unchanged), 200 on the user
routes. As admin, everything answers 200, including setting user 2's limit.

**Before the change:** endpoint permissions are off (`config/auth.toml`
`enable_auth_endpoint = false`), and the auth service has no permission rules
anyway (its `endpoints` table is empty). So every route only checks "is someone
logged in". Any normal user can call, for example:

- `/limits/put_limit`, `/limits/remove_limit`: **raise their own limits**
  (the ownership check allows their own id)
- `/admin/tasklist`, `/admin/taskstop`: see and **stop other users' tasks**
- `/admin/assign_obj_to_user`, `/admin/assign_app`: give objects or apps to anyone
- `/admin/get_monitor_info*`: see all users, objects and files

The frontend hides these pages from normal users, but the API doesn't.

**Proposal:** the backend now knows each user's role (added for the admin limits
list). Add an `admin_only: bool` field to `BlueprintInfo`. Set it on the
`/admin/*` routes and on the limit write routes. In `blueprint_handler.py`,
answer 403 when the user's role isn't `admin`. That's a small, contained change.

**Cost:** about 20 route definitions plus 10 lines in the handler. Admins see
no difference. Normal users get 403 where they previously had access they
shouldn't have.

### 2.2 Any user can change or delete system objects (security, high): DONE

**Implemented 2026-11-05:**
- New flag `BlueprintInfo.protect_system_objects`. When it's set, a non-admin
  gets 403 "Only admins may change system objects" if any object the route
  loads has owner 0. The log records "denied changing system object".
- It's set on the 28 routes that change or delete what they load:
  - `phases`: `baseimage_delete`, `baseimage_finalize`, `environment_create`,
    `environment_delete`, `environment_finalize`, `cfg_set_target`,
    `cfg_applist`, `cfg_tasklist`, `cfg_from_application`
  - `vm`: `config_set_pre_install`, `config_set_post_install`,
    `snapshot_create`, `snapshot_rollback`, `template_convert`, `delete`,
    `create`
  - `container`: `image_build`, `image_delete`, `image_create`,
    `image_create_root`
  - `files`/`apps`: `delete`, `update`, `delete_shared`, `update_shared`
- Start, run, connect and **clone** of system objects stay open to everyone,
  and so does everything on the user's own objects.
- This mattered in the UI too, not only through the API: the user dashboard
  lists the system objects (`templateDeb12`, `contx11`, …) next to the user's
  own, so a normal user could select a template and delete it.
- Environments have no owner of their own; they count as part of their object.

Tested with a throwaway normal user and a throwaway object marked owner 0,
both deleted afterwards:
- `baseimage_delete`, `baseimage_finalize`, `environment_create` and
  `container/image_delete` answered 403, and the object and its image stayed.
- The user could still clone it and delete their own copy.
- The admin could delete it.

Decided 2026-11-05: **admins only**. The `expert` role (the frontend has
"expert environment" pages) may not change system objects. Experts build
environments on their own copies, made by cloning a template.

**Before the change:** `DaasAuthenticator.verify_object` accepts objects of owner `0` (the
system templates such as `templateDeb12`, `contx11`, `contwine`) for every user
and every action. Through the API a normal user can delete the Debian template
(VM 115), and then nobody can create Debian desktops any more.

**Proposal:** owner-0 objects stay readable, startable and clonable for
everyone; **delete, modify and convert-to-template require role `admin`**.
This builds on 2.1: either mark those routes `admin_only=True`, if only admins
should delete or modify at all, or add a second flag that applies only when the
object's owner is 0.

### 2.3 Resource limits are enforced with `assert` (correctness)

**Today:** `assert await self.verify_demand(userid)` (5 places, in
`base_machine.py` and `object_container.py`) is the limit check. When a user is
over their limit:
- the user gets a generic 500 error instead of "limit reached"
- if Python ever runs with `-O`, asserts are removed and **limits stop working
  entirely**

**Proposal:** replace each one with
`if not await self.verify_demand(...): return <400 "Resource limit reached">`.
The frontend already shows the backend's error message.

### 2.4 Blocking calls inside the async server (performance)

**Today:** the backend is one asyncio event loop, but several things block it:
- every Docker SDK call (`docker` is synchronous)
- SSH commands (`adapter_ssh.py`, `subprocess.run`)
- Ceph commands (`ceph_base.py`)
- `du`/`df` for host info (`hostinfo.py`)

While one of them runs, *every* other request waits, including the Guacamole
streams of everyone else's desktops. That makes a desktop session freeze while
somebody else starts a container.

**Proposal:** wrap these calls in `await asyncio.to_thread(...)`. The logic
stays the same; only where it runs changes. Do it one adapter at a time (Docker
first, it's the most used), testing each.

### 2.5 Waiting for a Proxmox task can hang forever (robustness)

**Today:** `ProxmoxRestRequest.__read_task_sync` polls the task status in a
`while True` loop with no limit. If Proxmox keeps answering with an error (for
example the task disappeared, or the session expired), the request never ends.

**Proposal:** give up after a timeout (e.g. 10 minutes; a full clone takes
about 15 s here) and return an error.

### 2.6 Uploading a file into a running desktop ignores the target folder (probable bug)

**Today:** `fs_instances.py` (around line 310) works out `norm_folder` (the
folder the file should go to, Windows or Linux style) and then never uses it.
`inst_vminvoke_upload(filename, ...)` only gets the file name. I didn't change
this because I couldn't confirm from the agent code (`app/inst`) where the file
ends up and whether anyone relies on the current behavior.

**Proposal:** pass the folder to the agent, after checking in a desktop where
an uploaded file currently lands.

### 2.7 Smaller items

| Item | Today | Proposal |
|---|---|---|
| VMID range | Next VMID = highest in DB + 1, max 254. IDs freed by deletes are never reused, so after about 140 desktops in total no new VM can be created | Use the lowest free ID ≥ 116 (DB and Proxmox), or Proxmox's `/cluster/nextid` |
| Guacamole idle check (`guacamole_proxy.py`) | After 1.2 s of silence it only logs "GUAC DIFF EXCEEDED"; the disconnect line is commented out | Decide: delete the check, or make it a real timeout (minutes, not 1.2 s) |
| `phase_machine.py:107` | Logs all request arguments at *warning* level on every VM create (`DISKSIZE_ARGS`) | Debug level, and without the full `args` |
| "Filestore NOT initialized" on every start | `data/endpoint_info` is empty, so loading the endpoint permission files fails | If endpoint permissions stay off (see 2.1), skip loading them and drop the error |
| Shutdown | pika sometimes raises `AssertionError` while closing the heartbeat connection; it's caught and logged now | Harmless; could be silenced in `qmsg_heartbeat_receiver.disconnect` |
| `nest_asyncio` | Used to allow nested event loops | **Done 2026-11-06** (batch 2): the helpers that needed it are async now |
| `installer` `make reset` | Clears the DB but only lists the Proxmox VMs, so they become invisible leftovers (that's how VMs 116/117 happened) | Also destroy the desktop VMs (every VM except template 115) when `CONFIRM=yes` |

---

## 3. Dead code and commented-out code: DONE

**Cleaned 2026-11-05.** Nothing here changes what the app does: none of the
removed code was ever run.

### Deleted

- **About 105 functions and classes that nothing calls.** Found by searching
  all of `src` (Python, config, web templates) for each name. Deleting them was
  repeated until nothing new turned up, because helpers used only by dead code
  are dead too. Among them:
  - the Ceph per-desktop mount/unmount, keyring and permission helpers
    (`mount_inst` would have crashed anyway: it called a private method of
    another class)
  - `stop_plugins`, `stop_filesystems`
  - the password-hash helpers from before the auth service
  - the unused endpoint-permission lookups
  - the unused `fs_*` path and file helpers
  - `ReconnectHandler`
  - assorted unused database and task-manager getters
- **`ceph_actions.py` and `ceph_permissions.py`.** They were empty after that,
  so `Cephstore` now inherits `CephstoreBase` directly.
- **About 570 lines of commented-out code**, for example:
  - old implementations: `connect_legacy`, `migrate_database`, a 176-line
    `create_object_dict_from_app`, a 75-line `viewer_set_screen`,
    `synchronize_database_objects_proxmox`
  - imports from the old package name `daas_web`
  - commented debug `print`s and log lines
  - commented demo data
  - disabled alternatives (handshake options, `cascade=`, retries)

### Kept on purpose

| What | Why |
|---|---|
| `daas/proxy/guacamole_proxy.py`: the two commented `raise asyncio.CancelledError()` in the idle check | Part of open decision 2.7 (real timeout or remove the check) |
| `fs_instances.py`: the unused `norm_folder` | Part of open item 2.6 (upload ignores the target folder) |
| `db_samples.py` sample methods that now return empty lists | Called at start up by the sample import (`include_samples = true`) |
| `ORMFile`, `ORMApplication`, `ORMLimit`, `process_bind_param`, `process_result_value`, `daas/proxy/test_syntax.py` | Look unused to a search, but they create database tables, are SQLAlchemy hooks, or are pytest tests |
| `app/inst` (the agent inside the VMs) | Not cleaned for dead functions: it's started in the VMs with its own entry points (`cmdline.py`), which a search of the backend can't see |

### 2.8 Printing inside desktops: DONE

**Enabled 2026-11-05.** After a desktop boots, `PostbootTask._add_printer`:
1. creates the owner's queue `printer<owner>` on the print service
   (`create_printer.sh` in the extensions container; it's safe to run again).
   Before, that queue only appeared once the viewer had opened its printer
   websocket, so a job sent earlier would have had nowhere to go.
2. installs `design-printer` inside the desktop, pointing to
   `ipp://<extensions>:631/printers/printer<owner>`. On Linux it's also made
   the default destination; on Windows it's added with `printui`.

Tested end to end, with the printer websocket opened as the viewer does:
- **Container desktop** (`contx11` clone): `lp` produced `daas-print-test.pdf`
  (10.6 KB), which arrived over the websocket.
- **Debian VM desktop** (`templateDeb12` clone): `lp` produced
  `daas-vm-print-test.pdf` (6.4 KB).
- **Windows:** not tested, because no Windows template VM exists yet.

Desktops that were already running before this change get the printer the next
time they start.

### 2.9 SSH commands into desktops always "succeed" (correctness)

**Today:** `SshAdapter` (`daas/adapter/adapter_ssh.py`) does two things wrong:
- **It appends `&` to every command.** The desktop's shell runs the command in
  the background, so the exit code is always 0. Every failed command that the
  backend runs in a desktop is reported as success. For example, the printer
  check logs "Printer exists" even when `lpstat` says it doesn't, and "Printer
  added: True" only means the command was sent.
- **It decodes the output as `cp850`** (a Windows code page). German text from
  Linux desktops comes out garbled ("Ger�t" instead of "Gerät").

**Proposal:** drop the `&`, and decode as UTF-8 on Linux (keep cp850 only for
Windows desktops). It's a small change, but it affects every SSH call: commands
that "succeed" today may start reporting real errors. So it needs a round of
testing (start, clone, environments, uploads, printing) on Linux and Windows.

### Observation: limit rows of deleted users

The `limits` table has rows for ids 2 and 4–12, but the auth service has only
user 1. Limit rows are written only by `/limits/put_limit` (admin page), and
nothing removes them when a user is deleted in the auth service. Where these
rows came from isn't confirmed (the admin limitation page or earlier tests).
They're harmless today; removing a user's limit when the user is deleted would
keep the admin limits list correct.

---

## 4. Cleanup of 2026-11-06 (batch 1)

Bugs fixed:
- `db.toml include_samples` was never read: the samples were imported on
  every start. Now `false` really skips them (`db_plugin.py`).
- `logging.toml log_hypercorn = false` re-enabled the hypercorn access log
  instead of disabling it.
- `log_encode` was put on the formatter, where Python ignores it; it is now
  the encoding of the log files.
- The `container` log target had no switch in `logging.toml`, so there was no
  `container.log`; added `log_container = true`.
- Typo in the log line `task_authenitcation()`.

Note on levels: every logger uses `log_level`, `debug.log` included. With
`"INFO"` the `_log_debug` messages are not written anywhere; set `"DEBUG"`
to see them (documented in `logging.toml`).

Log noise (48.6k of the 58.8k lines in the current `debug.log`):
- `messaging.toml log_heartbeats = false` (one line per instance per second).
- `SQL (Select) <table>` and `GUAC DIFF EXCEEDED` are debug messages now.

Config keys that no code read were removed together with their dataclass
fields: `ceph.toml mappings_*`, `db.toml database, admin_credentials` and 8
`[samples]` keys, `files.toml folder_inst_env, instance_status_pidfile_name,
default_{wine,x11vnc}_image_{name,folder}`, `info.toml known_daas_containers`,
`logging.toml all_sublogs, no_sublogs`, `messaging.toml proxyfile`,
`vm.toml bridge_adapter_{inst,ceph,cluster}`. `token_length` is read (it was
documented as unused). `ProxmoxConfigStoreConfig.bridge_name_daas` is now
`bridge_name_inst`: it always held vmbr1, the instance network.

Files deleted (nothing used them): `app/inst/cmdline.py` (imported modules
that no longer exist), `app/inst/timings.py`, `push2ip.bash`,
`push2x11cont.bash`, `app/daas/messaging/runner_backend.py` and
`runner_local.py` (manual test scripts), `webroot/static/viewer_layout_old.js`,
`viewer-styles.css`, `my-processor.js` and 7 unreferenced PNGs (also not used
by the frontend repo), `src/Dockerfile` and the `docker-*` targets of
`src/Makefile`. `mkdocs.yml` and `gen_apidocs.py` moved to `archiv/` with the
docs they build.

Test and benchmark scripts deleted (`scripts/tests_*.bash`, `plot_*.py`,
the `tests-*` / `plots` targets of `src/Makefile`, `pandas` and `matplotlib`
in the venv); end-to-end tests will live in their own repository.
`scripts/entrypoint.bash` belonged to the deleted `src/Dockerfile`.

Repository: `.gitignore` covers `*.bak-*`, `.idea/` and
`installer/daas-ca.crt` (removed from git). That file was a copy: every host
creates its own CA in `/etc/nginx/ssl/daas-ca.crt` on `make daas-configure`
(`installer/daas/mkcert.bash`).

## 5. Readability refactor of 2026-11-06 (batch 2)

No behavior change. Checked by comparing the URL map before and after, by
calling all 124 non-test routes without login before and after (identical
responses) and by `make daas-check auth-check frontend-check`.

- **Routes are generated from `BlueprintInfo`.** The 141 route functions
  only called `handler.handle_frame(inspect.currentframe())`, which found the
  route config by the function's name. `BlueprintHandlerBase._add_route` now
  registers `info.url` for each info, with `info.name` as endpoint name, and
  calls `handle_request(info.name)`. The docstrings of the old functions are
  `BlueprintInfo.description`. Six infos had a different `url` than the
  route really served (only used in log lines); they now hold the real URL.
  `/errortest2` (test plugin, no info, always answered an error) is gone.
  The unused `testing` and `default_handler` parameters of
  `BlueprintHandler` were removed.
- **Backends:** `QwebBackend` has the `status()` all 17 backends repeated,
  and default `connect`/`disconnect` that only set `connected`. The six
  backends without a real connection (auth, task, instances, phases, admin,
  test) use those; the others keep theirs. Copy-pasted docstrings
  ("Database backend" on the node backend, ...) fixed. Only difference: the
  auth backend now reports `connected = False` after shutdown (it said
  `True`).
- **No more nested event loops:** `_loop_exec` and
  `Processor.create_async_response` ran coroutines with
  `run_until_complete` inside the running loop, which is why `nest_asyncio`
  was needed. The callers (`_get_request_context`, `_init_timing`,
  `_create_error_response`, the file and template processors) are async and
  `await` instead; `nest_asyncio` is out of the code, the Makefile and
  `pyproject.toml`.
- **`print()` → logger:** `main.py` stage banners are `runtime` log lines;
  a crash is now logged with message and traceback (before only the
  exception type was printed). Also `config_machine.py`, `ProxmoxApi.py`,
  `db_mappings.py`, `streams.py`, `auth_dummy.py`, the runtime state, and a
  leftover `TOOLS_INFO` debug print in `infotools.py`.

