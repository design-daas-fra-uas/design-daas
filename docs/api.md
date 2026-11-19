# DaaS backend API

Generated from the route definitions (`src/app/plugins/**/*_routes.py`) by
`make api-docs` in `src/`; do not edit by hand. The running backend serves
the same reference at `/api/docs` (HTML) and `/api/docs.json`.

Requests send their arguments as form fields (multipart) or JSON; every
route except the public ones needs `Authorization: Bearer <token>` from the
auth service. `X-Request-ID` is optional and is written into the logs.

## default

### `POST /`

Default Endpoint

- Access: login
- Response: `text/html`

### `POST /debug`

Default Endpoint

- Access: login
- Response: `text/html`

### `GET /favicon.ico`

Default Endpoint

- Access: public
- Response: `*/*`

### `GET /robots.txt`

Endpoint for crawlers

- Access: public
- Response: `text/html`

## auth

### `GET /login`

Default Browsertest Endpoint

- Access: public
- Response: `text/html`

### `POST /login`

Default Browsertest Endpoint

- Access: public
- Required: `username`, `password`
- Response: `text/html`

### `GET /js/login.js`

js login endpoint

- Access: public
- Response: `text/javascript`

## task

### `POST /tasks/get`

Returns specified task

- Access: login
- Required: `id_task`
- Response: `application/json`

### `POST /tasks/stop`

Stops specified task

- Access: login
- Optional: `id_task`, `id_object`, `id_instance`
- Response: `application/json`

### `POST /tasks/list`

Returns specified tasklist

- Access: login
- Required: `state`
- Optional: `id_object`, `id_instance`
- Response: `application/json`

### `POST /tasks/status`

Returns status for all tasks

- Access: login
- Response: `application/json`

## vm

### `POST /vm/list`

Get vm list from proxmox api

- Access: login
- Optional: `onlyuser`, `onlydaas`, `detailed`
- Response: `application/json`

### `POST /vm/status`

Get vm status from proxmox api

- Access: login
- Required: `id`
- Response: `application/json`

### `POST /vm/config_get`

Retrieves vm configuration

- Access: login
- Required: `id`
- Response: `application/json`

### `POST /vm/config_set_pre_install`

Sets vm configuration (pre)

- Access: login (system objects: admin)
- Required: `id`, `name`, `os_type`, `cores`, `memsize`, `disksize`, `iso_installer`, `keyboard_layout`
- Optional: `ceph_pool`
- Response: `application/json`

### `POST /vm/config_set_post_install`

Sets vm configuration (post)

- Access: login (system objects: admin)
- Required: `id`, `name`, `keyboard_layout`
- Response: `application/json`

### `POST /vm/snapshot_list`

Lists all snapshots of a vm via proxmox api

- Access: login
- Required: `id`
- Response: `application/json`

### `POST /vm/snapshot_create`

Creates snapshots for a specific vm via proxmox api

- Access: login (system objects: admin)
- Required: `id`, `snapname`, `desc`
- Response: `application/json`

### `POST /vm/snapshot_rollback`

Restores snapshots of a vm via proxmox api

- Access: login (system objects: admin)
- Required: `id`, `snapname`
- Response: `application/json`

### `POST /vm/template_convert`

Converts vm object into template via proxmox api

- Access: login (system objects: admin)
- Required: `id`, `disk`
- Optional: `kb`
- Response: `application/json`

### `POST /vm/start`

Starts vm object

- Access: login
- Required: `id`, `id_env`
- Optional: `connect`
- Response: `application/json`

### `POST /vm/stop`

Stops vm object

- Access: login
- Required: `id_instance`
- Response: `application/json`

### `POST /vm/delete`

Deletes vm object

- Access: login (system objects: admin)
- Required: `id`
- Response: `application/json`

### `POST /vm/create`

Creates vm object

- Access: login (system objects: admin)
- Required: `id`, `name`, `cores`, `memsize`, `disksize`, `kb`, `os_type`, `viewer_contype`, `viewer_resolution`
- Optional: `ceph_public`, `ceph_shared`, `ceph_user`, `viewer_resize`, `viewer_scale`
- Response: `application/json`

### `POST /vm/clone`

Creates vm object

- Access: login
- Required: `id`, `newid`, `name`, `kb`
- Optional: `ceph_public`, `ceph_shared`, `ceph_user`, `snapname`
- Response: `application/json`

## container

### `POST /container/daemon_info`

Returns info from utilized docker daemon

- Access: login
- Response: `application/json`

### `POST /container/image_inspect`

Returns info from specified docker image

- Access: login
- Required: `id`
- Response: `application/json`

### `POST /container/image_build`

Builds specified docker image

- Access: login (system objects: admin)
- Required: `id`
- Response: `application/json`

### `POST /container/image_delete`

Deletes specified docker image

- Access: login (system objects: admin)
- Required: `id`
- Response: `application/json`

### `POST /container/image_list`

Lists docker images

- Access: login
- Optional: `onlyuser`, `onlydaas`, `detailed`
- Response: `application/json`

### `POST /container/container_start`

Starts container

- Access: login
- Required: `id`
- Optional: `connect`
- Response: `application/json`

### `POST /container/container_stop`

Stops container

- Access: login
- Required: `id_instance`
- Response: `application/json`

### `POST /container/image_create`

Creates specified container object by using uploaded dockerfile

- Access: login (system objects: admin)
- Required: `id`, `name`, `cores`, `memsize`, `disksize`, `viewer_contype`, `viewer_resolution`
- Optional: `ceph_public`, `ceph_shared`, `ceph_user`, `viewer_resize`, `viewer_scale`
- Files: `dockerfile`
- Response: `application/json`

### `POST /container/image_create_root`

Creates specified container object by using template file

- Access: login (system objects: admin)
- Required: `id`, `name`, `cores`, `memsize`, `disksize`, `rootimage`, `viewer_contype`, `viewer_resolution`
- Optional: `ceph_public`, `ceph_shared`, `ceph_user`, `viewer_resize`, `viewer_scale`
- Response: `application/json`

### `POST /container/image_clone`

Clones container image

- Access: login
- Required: `id`, `newid`, `name`
- Response: `application/json`

### `POST /container/container_list`

Lists container

- Access: login
- Optional: `onlyuser`, `onlydaas`, `detailed`
- Response: `application/json`

### `POST /container/container_logs`

Returns container logs

- Access: login
- Required: `id`
- Response: `application/json`

## inst

### `POST /inst/vminvoke_app`

Invokes (non-blocking) app command

- Access: login
- Required: `id`, `id_env`, `cmd`, `args`
- Response: `application/json`

### `POST /inst/vminvoke_cmd`

Invokes (blocking) command

- Access: login
- Required: `id`, `id_env`, `cmd`, `args`
- Response: `application/json`

### `POST /inst/vminvoke_ssh`

Invokes (blocking) command

- Access: login
- Required: `id`, `id_env`, `cmd`, `args`
- Response: `application/json`

### `POST /inst/vminvoke_action`

Invokes (blocking) action command

- Access: login
- Required: `id`, `id_env`, `cmd`, `args`
- Response: `application/json`

### `POST /inst/vminvoke_resolution`

Invokes (blocking) resolution command

- Access: login
- Required: `id`, `id_env`, `cmd`, `args`
- Response: `application/json`

### `POST /inst/vminvoke_ospackage`

Invokes (blocking) action command

- Access: login
- Required: `id`, `id_env`, `cmd`, `args`
- Response: `application/json`

### `POST /inst/vminvoke_upload`

Invokes (blocking) action command

- Access: login
- Required: `id`, `id_env`
- Optional: `execute`
- Files: `file`
- Response: `application/json`

### `POST /inst/vminvoke_filesystem`

Invokes (blocking) action command

- Access: login
- Required: `id`, `id_env`, `cmd`, `args`
- Optional: `ceph_public`, `ceph_shared`, `ceph_user`
- Response: `application/json`

### `POST /inst/list`

Invokes (blocking) action command

- Access: login
- Response: `application/json`

### `POST /inst/connection_test_icmp`

Invokes (blocking) icmp test command ()ping)

- Access: login
- Required: `id`, `id_env`
- Response: `application/json`

### `POST /inst/connection_test_ssh`

Invokes (blocking) ssh test command

- Access: login
- Required: `id`, `id_env`
- Response: `application/json`

### `POST /inst/vminvoke_rtt`

Invokes (blocking) roundtrip command

- Access: login
- Required: `id`, `id_env`, `iter`, `name`, `cmd`, `args`
- Response: `application/json`

## phases

### `POST /phases/baseimage_create`

Creates new object

- Access: login
- Required: `id`, `obj_type`, `name`, `cores`, `memsize`, `disksize`, `viewer_contype`, `viewer_resolution`
- Optional: `os_type`, `rootimage`, `dockerfile`, `kb`, `ceph_public`, `ceph_shared`, `ceph_user`, `viewer_resize`, `viewer_scale`
- Response: `application/json`

### `POST /phases/baseimage_clone`

Clones object

- Access: login
- Required: `id`, `newid`, `name`
- Optional: `ceph_public`, `ceph_shared`, `ceph_user`, `kb`, `snapname`
- Response: `application/json`

### `POST /phases/baseimage_delete`

Deletes object

- Access: login (system objects: admin)
- Required: `id`
- Response: `application/json`

### `POST /phases/baseimage_start`

Starts object

- Access: login
- Required: `id`
- Optional: `connect`
- Response: `application/json`

### `POST /phases/baseimage_stop`

Stop object

- Access: login
- Required: `id_instance`
- Optional: `force`
- Response: `application/json`

### `POST /phases/baseimage_finalize`

Finalizes object

- Access: login (system objects: admin)
- Required: `id`
- Response: `application/json`

### `POST /phases/object_status`

Returns object status

- Access: login
- Required: `id`
- Response: `application/json`

### `POST /phases/object_list`

Lists objects

- Access: login
- Optional: `detailed`, `onlyuser`, `onlydaas`
- Response: `application/json`

### `POST /phases/environment_create`

Create environment

- Access: login (system objects: admin)
- Required: `id`, `name`
- Optional: `dockerfile`
- Response: `application/json`

### `POST /phases/environment_get`

Returns environment

- Access: login
- Required: `id`, `name`
- Response: `application/json`

### `POST /phases/environments_get`

Returns environment list

- Access: login
- Required: `id`
- Response: `application/json`

### `POST /phases/environment_delete`

Deletes environment

- Access: login (system objects: admin)
- Required: `id`, `name`
- Response: `application/json`

### `POST /phases/environment_start`

Starts environment

- Access: login
- Required: `id`, `name`
- Optional: `connect`
- Response: `application/json`

### `POST /phases/environment_run`

Runs environment

- Access: login
- Required: `id`, `env`
- Optional: `connect`
- Response: `application/json`

### `POST /phases/environment_stop`

Stops environment

- Access: login
- Required: `id`, `name`
- Optional: `force`
- Response: `application/json`

### `POST /phases/environment_finalize`

Finalizes environment

- Access: login (system objects: admin)
- Required: `id`, `name`
- Response: `application/json`

### `POST /phases/cfg_set_target`

Sets target for object or environment

- Access: login (system objects: admin)
- Required: `id`, `env`, `target`
- Response: `application/json`

### `POST /phases/cfg_applist`

Sets applist for object or environment

- Access: login (system objects: admin)
- Required: `id`, `env`, `applist`
- Response: `application/json`

### `POST /phases/cfg_tasklist`

Sets tasklist for object or environment

- Access: login (system objects: admin)
- Required: `id`, `env`, `tasklist`
- Response: `application/json`

### `POST /phases/cfg_from_application`

Sets config from app for object or environment

- Access: login (system objects: admin)
- Required: `id`, `env`, `appid`
- Response: `application/json`

### `POST /phases/baseimage_create_from_app`

Creates object from app

- Access: login
- Required: `id`, `env`, `appid`, `name`
- Optional: `run`
- Response: `application/json`

### `POST /phases/baseimage_clone_from_app`

Clones object from app

- Access: login
- Required: `newid`, `env`, `appid`, `name`
- Optional: `id`, `run`
- Response: `application/json`

## proxy

### `GET /viewer/template/<id>`

Get viewer template

- Access: login
- Optional: `id_env`
- Query: `id`
- Response: `text/html`

### `POST /viewer/check/<id_instance>`

Check viewer connection

- Access: login
- Required: `token`
- Query: `id_instance`
- Response: `application/json`

### `POST /viewer/info/<id_instance>`

Returns viewer info for connection

- Access: login
- Required: `token`
- Optional: `resolutions`
- Query: `id_instance`
- Response: `application/json`

### `WEBSOCKET /wss/connect/<id_instance>/<token>`

Forward all sub-path WebSocket requests to guacamole

- Access: login
- Query: `id_instance`, `token`
- Response: `application/json`

### `POST /viewer/connect`

Connects viewer

- Access: login
- Required: `id`, `id_env`, `contype`
- Response: `application/json`

### `POST /viewer/disconnect`

Disconnects viewer

- Access: login
- Required: `id`, `id_env`
- Response: `application/json`

### `POST /viewer/set_screen/<id_instance>`

Sets viewer screen settings

- Access: login
- Required: `token`, `contype`, `resolution`, `resize`, `scale`
- Query: `id_instance`
- Response: `application/json`

## extensions

### `WEBSOCKET /extensions/printer_ws/<token>`

Forward all printer requests

- Access: login
- Query: `token`
- Response: `text/html`

### `WEBSOCKET /extensions/audio_ws/<string:token>`

Forward all audio requests

- Access: login
- Query: `token`
- Response: `text/html`

## node

### `POST /node/vmconfigure_dhcp`

Configures dhcp for specified instance

- Access: login
- Required: `id`, `id_env`
- Response: `text/html`

### `POST /node/vmconfigure_iptables`

Configures iptables for specified instance

- Access: login
- Required: `id`, `id_env`
- Response: `text/html`

### `POST /node/vminvoke_upload`

Uploads file to host

- Access: login
- Required: `file`
- Response: `text/html`

## admin

### `POST /admin/get_monitor_info`

Returns monitor info

- Access: admin
- Optional: `id_owner`
- Response: `application/json`

### `POST /admin/get_monitor_info_tasks`

Returns monitor info tasks

- Access: admin
- Optional: `id_owner`
- Response: `application/json`

### `POST /admin/get_monitor_info_apps`

Returns app infos

- Access: admin
- Optional: `id_owner`
- Response: `application/json`

### `POST /admin/get_monitor_info_files`

Returns file infos

- Access: admin
- Optional: `id_owner`
- Response: `application/json`

### `POST /admin/get_monitor_info_websockets`

Returns websocket infos

- Access: admin
- Optional: `id_owner`
- Response: `application/json`

### `POST /admin/get_monitor_info_host`

Returns host infos

- Access: admin
- Optional: `id_owner`
- Response: `application/json`

### `POST /admin/get_monitor_info_objects`

Returns object infos

- Access: admin
- Optional: `id_owner`
- Response: `application/json`

### `POST /admin/get_monitor_info_utilization`

Returns resource utilization infos

- Access: admin
- Optional: `id_owner`
- Response: `application/json`

### `POST /admin/get_monitor_info_limits`

Returns resource limit infos

- Access: admin
- Optional: `id_owner`
- Response: `application/json`

### `POST /admin/assign_obj_to_user`

Assigns object to user

- Access: admin
- Required: `id`, `owner`
- Response: `application/json`

### `POST /admin/assign_app`

Assigns app

- Access: admin
- Required: `appid`, `owner`
- Response: `application/json`

### `POST /admin/tasklist`

Lists tasks for user, object or instance

- Access: admin
- Required: `id_owner`, `id_object`, `id_instance`, `state`
- Response: `application/json`

### `POST /admin/taskstop`

Stops task by user, object or instance

- Access: admin
- Required: `id_owner`, `id_task`, `id_object`, `id_instance`
- Response: `application/json`

### `POST /admin/delete_user_data`

Deletes everything a user owns before their account is deleted

- Access: admin
- Required: `id_owner`
- Response: `application/json`

## info

### `POST /monitoring/dashboard_info`

Returns dashboardinfo state

- Access: login
- Response: `application/json`

### `POST /monitoring/get_monitor_info`

Returns monitor info

- Access: login
- Response: `application/json`

### `POST /monitoring/get_monitor_info_tasks`

Returns monitor info tasks

- Access: login
- Response: `application/json`

### `POST /monitoring/get_monitor_info_apps`

Returns app infos

- Access: login
- Response: `application/json`

### `POST /monitoring/get_monitor_info_files`

Returns file infos

- Access: login
- Response: `application/json`

### `POST /monitoring/get_monitor_info_websockets`

Returns websocket infos

- Access: login
- Response: `application/json`

### `POST /monitoring/get_monitor_info_host`

Returns host infos

- Access: login
- Response: `application/json`

### `POST /monitoring/get_monitor_info_objects`

Returns object infos

- Access: login
- Response: `application/json`

### `POST /monitoring/get_monitor_info_utilization`

Returns resource utilization infos

- Access: login
- Response: `application/json`

### `POST /monitoring/get_monitor_info_limits`

Returns resource limit infos

- Access: login
- Response: `application/json`

### `POST /monitoring/get_quota`

Returns the caller's resource limits (own entry or the limits.toml fallback) next to what they currently use: VMs, containers, objects, CPUs, memory and disk

- Access: login
- Response: `application/json`

### `POST /monitoring/get_system_status`

Returns the health of the stack, like `make status`: DaaS backend, auth service (actuator), service containers and frontend (admins only)

- Access: admin
- Response: `application/json`

## limits

### `POST /limits/get_limit`

Returns specified limit

- Access: login
- Required: `id_owner`
- Response: `application/json`

### `POST /limits/put_limit`

Stores specified limit

- Access: admin
- Required: `id_owner`, `vm_max`, `container_max`, `obj_max`, `cpu_max`, `mem_max`, `dsk_max`
- Response: `application/json`

### `POST /limits/remove_limit`

Removes specified limit

- Access: admin
- Required: `id_owner`
- Response: `application/json`

### `POST /limits/list_limits`

Lists specified limit

- Access: admin
- Response: `application/json`

## file

### `POST /files/get`

Returns specified file object

- Access: login
- Required: `id`
- Response: `application/json`

### `POST /files/delete`

Deletes specified file object

- Access: login (system objects: admin)
- Required: `id`
- Response: `application/json`

### `POST /files/delete_shared`

Deletes specified shared file object

- Access: login (system objects: admin)
- Required: `id`
- Response: `application/json`

### `POST /files/list`

Lists specified file objects

- Access: login
- Required: `choice`
- Response: `application/json`

### `POST /files/create`

Creates specified file object

- Access: login
- Required: `id`, `filename`, `filepath`, `version`, `os_type`
- Files: `file`
- Response: `application/json`

### `POST /files/update`

Update specified file object

- Access: login (system objects: admin)
- Required: `id`, `filename`, `filepath`, `version`, `os_type`
- Files: `file`
- Response: `application/json`

### `POST /files/create_shared`

Creates specified shared file object

- Access: login
- Required: `id`, `filename`, `filepath`, `version`, `os_type`
- Files: `file`
- Response: `application/json`

### `POST /files/update_shared`

Update specified shared file object

- Access: login (system objects: admin)
- Required: `id`, `filename`, `filepath`, `version`, `os_type`
- Files: `file`
- Response: `application/json`

### `POST /apps/get`

Returns specified app object

- Access: login
- Required: `id`
- Response: `application/json`

### `POST /apps/delete`

Deletes specified app object

- Access: login (system objects: admin)
- Required: `id`
- Response: `application/json`

### `POST /apps/delete_shared`

Deletes specified shared app object

- Access: login (system objects: admin)
- Required: `id`
- Response: `application/json`

### `POST /apps/list`

Lists specified app objects

- Access: login
- Required: `choice`
- Response: `application/json`

### `POST /apps/create`

Creates specified app object

- Access: login
- Required: `id`, `name`, `id_file`, `id_template`, `os_type`, `installer`, `installer_args`, `installer_type`, `target`, `target_args`, `version`
- Files: `file`
- Response: `application/json`

### `POST /apps/update`

Update specified app object

- Access: login (system objects: admin)
- Required: `id`, `name`, `id_file`, `id_template`, `os_type`, `installer`, `installer_args`, `installer_type`, `target`, `target_args`, `version`
- Files: `file`
- Response: `application/json`

### `POST /apps/create_shared`

Creates specified shared app object

- Access: login
- Required: `id`, `name`, `id_file`, `id_template`, `os_type`, `installer`, `installer_args`, `installer_type`, `target`, `target_args`, `version`
- Files: `file`
- Response: `application/json`

### `POST /apps/update_shared`

Update specified shared app object

- Access: login (system objects: admin)
- Required: `id`, `name`, `id_file`, `id_template`, `os_type`, `installer`, `installer_args`, `installer_type`, `target`, `target_args`, `version`
- Files: `file`
- Response: `application/json`
