# wine: Windows apps desktop image

The Docker image behind **Wine container instances**: a Linux desktop with
Wine, so users can run Windows programs in a container instead of a full
Windows VM. It is the default root image for new containers
(`DEFAULT_CNT_IMAGE` in `src/app/plugins/platform/phases/phases_tasks.py`).
The DaaS backend starts one container per instance from it, and the user
sees its desktop in the browser (guacd → VNC).

## What is in the image

Debian trixie with:

- **Wine 10** from Debian (64 + 32 bit) and **winetricks**
- A ready Wine prefix in `/root/.wine` (`WINEPREFIX`, 64 bit) with the
  Microsoft core fonts (arial, corefonts), created at build time
- 32-bit sound/SDL libraries, mono, cabextract/7z/unzip, zenity, winbind
- A test app as `C:\app.exe` (Thunderbird 115 installer)
- **Desktop**: Xtigervnc (X server + VNC server in one) at 1280x800, qtile
  window manager, wallpaper `daas.jpg`
- **Linux apps**: Firefox, LibreOffice, gedit, kitty, xterm, rofi, calculators
- **Sound**: pulseaudio with a virtual speaker/microphone
- **Printing**: cups
- **Shared folders**: ceph client
- **The DaaS agent** (`daas.runner_instance`): code from
  `src/app/daas/messaging` + `src/app/inst`. It is how the backend controls
  the instance, and it starts the Windows apps.

## What runs in a container

`entrypoint.bash` starts everything, in this order:

| Process | Port | Why |
|---|---|---|
| sshd | 22 | The backend runs commands in the instance (root, key `/root/.ssh/id_rsa` of the host) |
| Xtigervnc `:0` | 5900 | The desktop, 1280x800. guacd connects here with the VNC password |
| pulseaudio | 4713 | Sound; the extensions container connects over TCP |
| mic listener (`nc`) | 8080 | Microphone audio from the extensions container → virtual speaker |
| cupsd | 631 | Printing |
| DaaS agent | — | Connects to RabbitMQ on the docker host (`172.17.0.1:5672`), starts apps on request |
| qtile | — | Window manager; the container stops when it stops |

The agent runs as root, so Windows apps run in `/root/.wine`. In an ssh
shell `WINEPREFIX` is set too, so `wine 'C:\app.exe'` works there as well.

Shortcuts on the desktop: `Alt+Ctrl+` `s` terminal, `b` Firefox, `e` gedit,
`g` calculator, `r` app launcher, `w` window list, `q` close window,
`n`/`p` next/previous layout, `f` floating (see `config.py`).

## How it is used

1. `make images` in `installer/` (step 4 of `make install`) builds this
   image with two tags:
   - `wine`: the root image the backend derives user images from
     (the frontend sends it as `rootimage`; `DEFAULT_CNT_IMAGE` in
     `src/app/plugins/platform/phases/phases_tasks.py`)
   - `daas.contwine`: what the sample container object `contwine` runs
     (`src/app/daas/db/db_samples.py`)
2. A user environment gets a Dockerfile `FROM wine` / `FROM daas.contwine`
   plus the user's files and installers; the backend builds and starts it.
3. Starting an instance runs a container from it; the backend reaches it on
   its docker IP (`172.17.0.x`) via ssh, VNC and RabbitMQ.

## Commands

From `installer/` (normal use):

```bash
make wine-install       # build the image (both tags)
make wine-status        # installed? when was it built?
make wine-reinstall     # delete + build, e.g. after agent code changes in src/
make wine-delete        # remove the image (both tags)
```

From `installer/wine/` (working on the image itself), as root:

| Command | What it does |
|---|---|
| `make build` | Copies the agent + ssh key into the build context and downloads `app.exe` once (`make prepare`), builds `wine` + `daas.contwine` |
| `make check` | Starts a test container, checks the desktop processes and ports, then Wine: prefix, fonts, test app and running `wine cmd /c echo`. Removes it again. Run it after every change |
| `make run` | Starts a test container named `wine`: VNC on `127.0.0.1:5902`, ssh on `127.0.0.1:2222` |
| `make shell` | Bash inside the test container |
| `make stop` | Removes the test container |
| `make clean` | Removes the test container, the image and the copied/downloaded files |

Options: `VNC_PASSWORD=...`, `VNC_PORT=...`, `SSH_PORT=...`,
`SSH_KEY=...`, `BUILDOPT=--no-cache`.

Try a Windows app in a test container:

```bash
make run
vncviewer 127.0.0.1:5902                 # password user1234
docker exec -e DISPLAY=:0 wine wine 'C:\app.exe'
ssh -p 2222 root@127.0.0.1               # with the host's /root/.ssh/id_rsa
make stop
```

## Things to know

- **Rebuild after changing the agent code** (`src/app/daas/messaging`,
  `src/app/inst`): it is copied into the image at build time. Running
  instances keep the old code until they are recreated.
- **VNC password** `user1234` is set at build time (`VNC_PASSWORD`). guacd
  logs in with `vnc_password` from `src/app/daas/objects/config_factory.py`:
  change both together.
- **The ssh key** comes from `/root/.ssh/id_rsa.pub` (created by
  `make deps`). After a new key, rebuild the image.
- The build downloads the core fonts (winetricks, from sourceforge) and,
  once, `app.exe` (mozilla.net): it needs internet access.
- The test container's agent connects to RabbitMQ like a real instance; it
  is harmless and disappears when the container is removed.

## Files

| File | Content |
|---|---|
| `Dockerfile` | The image |
| `entrypoint.bash` | Starts the processes above |
| `config.py` | qtile config (keys, layouts, wallpaper) |
| `check.bash` | Smoke test behind `make check` |
| `Makefile` | The commands above |
| `daas.jpg`, `daas-logo.png` | Wallpaper and logo |
| `agent/`, `authorized_keys`, `app.exe` | Generated/downloaded by `make prepare`, not committed |
