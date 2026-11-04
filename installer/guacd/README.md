# guacd: remote desktop proxy

**guacd** is the Apache Guacamole proxy daemon. It is what makes an
instance's desktop visible in the browser: it speaks VNC, RDP and SSH to
the instances and the Guacamole protocol to the DaaS backend, which passes
it through a websocket to `guacamole.js` in the browser
([guacamole-client](../guacamole-client/README.md)).

```
browser (guacamole.js) ⇄ websocket ⇄ DaaS backend ⇄ guacd :4822 ⇄ VNC/RDP/SSH of the instance
```

| Protocol | Used for (`viewer_contype` of the object) |
|---|---|
| VNC | Most sessions: `instvnc` (the VNC server in a container or VM, e.g. x11vnc/wine on port 5900) and `sysvnc` (the Proxmox VM console) |
| RDP | `rdp` connections to Windows VMs |
| SSH | SSH sessions |

## What is in the image

guacamole-server **1.5.4**, built from source on Debian bookworm:

- The source `guacamole-server-1.5.4.tar.gz` is shipped in this folder
  (the Apache mirror URLs are not stable).
- Built with VNC (libVNCServer), RDP (FreeRDP 2), SSH (libssh2), sound
  (pulse, vorbis) and webp images. Telnet and Kubernetes are not built.
- **ghostscript**: guacd converts print jobs from RDP sessions to PDF with it.
- bookworm, not trixie: guacd 1.5.4 needs FreeRDP 2, and trixie only has
  FreeRDP 3.

## How it is used

- Container **`daas-0-guacd`** from image **`daas-0-guacd`**.
- The **DaaS backend starts it** on its own start and stops it on its stop
  (`[service_containers]` in `src/config/container.toml`), with 2 CPUs and
  2 GiB memory, published on `127.0.0.1:4822` (only the host can reach it).
- The backend connects to it at `guacd = "127.0.0.1:4822"`
  (`src/config/proxy.toml`); guacd itself connects out to the instances.
- guacd runs as PID 1 in the foreground: if it dies, the container stops
  and the backend notices.
- Log level: `GUACD_LOG_LEVEL` (default `debug`, every instruction is
  logged; `info` is much quieter).

## Commands

From `installer/` (normal use):

```bash
make guacd-install      # build the image; a running daas-0-guacd is restarted from it
make guacd-status       # running / stopped / not installed
make guacd-logs         # follow the guacd log
make guacd-restart      # restart the container
make guacd-stop | guacd-start
make guacd-reinstall    # delete + build + start
make guacd-delete       # stop it and remove the image
```

**Restarting guacd disconnects every open desktop session** in the
browser; users have to reconnect. Do it when nobody is working.

From `installer/guacd/` (working on the image itself), as root:

| Command | What it does |
|---|---|
| `make build` | Builds `daas-0-guacd` from the shipped source. A running container keeps the old image until it is restarted |
| `make check` | Starts a test container `daas-0-guacd-test` without published ports (does not clash with the running guacd), checks guacd runs as PID 1, asks it for VNC, RDP and SSH over the Guacamole protocol and checks ghostscript. Removes it again |
| `make clean` | Removes the image |

## Updating guacd

1. Download `guacamole-server-<version>.tar.gz` from
   <https://guacamole.apache.org/releases/> into this folder, remove the
   old one.
2. Set `GUACD_VERSION` in the `Makefile`.
3. `make build && make check`, then `make guacd-restart` in `installer/`
   and test a VNC and an RDP session in the browser.

Keep the client in mind: the browser side
([guacamole-client](../guacamole-client/README.md)) must speak the same
protocol version. guacd 1.6 builds with FreeRDP 2 or 3, so from 1.6 on the
base image can move to trixie.

## Files

| File | Content |
|---|---|
| `Dockerfile` | Build of guacd + ghostscript |
| `guacamole-server-1.5.4.tar.gz` | guacd source |
| `check.bash` | Smoke test behind `make check` |
| `Makefile` | build, check, clean |
