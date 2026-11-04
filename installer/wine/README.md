# wine: Windows apps desktop image

The Docker image behind **Wine container instances**: the
[x11vnc](../x11vnc/README.md) Linux desktop plus Wine, so users can run
Windows programs in a container instead of a full Windows VM. It is the
default root image for new containers (`DEFAULT_CNT_IMAGE` in
`src/app/plugins/platform/phases/phases_tasks.py`).

## What is in the image

Everything from x11vnc, plus:

- **Wine 10** from Debian (64 + 32 bit) and **winetricks**
- A ready Wine prefix in `/root/.wine` (`WINEPREFIX`, 64 bit) with the
  Microsoft core fonts (arial, corefonts), created at build time
- 32-bit sound/SDL libraries, mono, cabextract/7z/unzip, zenity, winbind
- A test app as `C:\app.exe` (Thunderbird 115 installer)
- A 1280x800 desktop (`VNC_GEOMETRY`; x11vnc has 1920x1080)

## What runs in a container

Exactly what runs in x11vnc (it uses the x11vnc entrypoint, no own one):
sshd :22, Xtigervnc :5900, pulseaudio, mic listener :8080, cupsd, the DaaS
agent and qtile. See the [x11vnc README](../x11vnc/README.md#what-runs-in-a-container).

Windows apps are started by the DaaS agent, which runs as root, so they
run in `/root/.wine`. In an ssh shell in the container `WINEPREFIX` is set
too, so `wine C:\\app.exe` works there as well.

## How it is used

1. `make images` in `installer/` (step 4 of `make install`) builds x11vnc
   first, then this image with two tags:
   - `wine`: the root image the backend derives user images from
     (`default_wine_image_name` in `src/config/files.toml`)
   - `daas.contwine`: what the sample container object `contwine` runs
     (`src/app/daas/db/db_samples.py`)
2. A user environment gets a Dockerfile `FROM wine` / `FROM daas.contwine`
   plus the user's files and installers; the backend builds and starts it
   like any container instance.

## Commands

From `installer/` (normal use):

```bash
make wine-install       # build the image (both tags); needs the x11vnc image
make wine-status        # installed? when was it built?
make wine-reinstall     # delete + build
make wine-delete        # remove the image (both tags)
```

From `installer/wine/` (working on the image itself), as root:

| Command | What it does |
|---|---|
| `make build` | Checks the x11vnc image exists, downloads `app.exe` once (`make prepare`), builds `wine` + `daas.contwine` |
| `make check` | Starts a test container, checks the desktop processes and ports, then Wine: prefix, fonts, test app and running `wine cmd /c echo`. Removes it again |
| `make run` | Starts a test container named `wine`: VNC on `127.0.0.1:5902`, ssh on `127.0.0.1:2222` |
| `make shell` | Bash inside the test container |
| `make stop` | Removes the test container |
| `make clean` | Removes the test container, the image and `app.exe` |

Options: `VNC_PORT=...`, `SSH_PORT=...`, `BUILDOPT=--no-cache`.

Try a Windows app in a test container:

```bash
make run
vncviewer 127.0.0.1:5902                 # password user1234
docker exec -e DISPLAY=:0 wine wine 'C:\app.exe'
make stop
```

## Things to know

- **Rebuild wine after every x11vnc rebuild.** It is built `FROM x11vnc`, so
  agent code, ssh key, VNC password and entrypoint fixes only reach wine
  instances after `make wine-install`. `make images` does both in the right
  order.
- The build downloads the core fonts (winetricks, from sourceforge) and,
  once, `app.exe` (mozilla.net): it needs internet access.
- Running instances keep their old image until they are recreated.

## Files

| File | Content |
|---|---|
| `Dockerfile` | Wine on top of the x11vnc image |
| `Makefile` | The commands above |
| `check.bash` | Smoke test behind `make check` |
| `app.exe` | Test app, downloaded by `make prepare`, not committed |
