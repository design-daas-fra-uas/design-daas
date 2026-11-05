# extensions: printing for the instances

VNC has no printing, so the **extensions container** adds it: when a user
prints in an instance (container or VM), the job goes to a per-user PDF
printer in this container, and the PDF ends up as a download in the user's
browser.

```
app in the instance ─IPP→ CUPS :631 (printer "printer<user id>", cups-pdf)
                               │ PDF written to files/<printer>/
                               ↓ scripts/postprocess.sh → POST /api/vnc/file
browser ←websocket← DaaS backend ←websocket :8010 /vnc/printer?id=printer<user id>  (server.js)
```

The **microphone** does not use this container: the DaaS backend sends the
audio straight to the instance (`pacat` to its port 8080, see
`src/app/daas/proxy/proxy_extensions.py`).

## What is in the image (`VNCService/`)

Ubuntu 22.04 with:

- **CUPS + cups-pdf** on port 631, open to the network (`scripts/cupsd.conf`)
  so the instances can print over IPP
- **server.js** (Node.js 18, express) on port 8010:
  - websocket `/vnc/printer?id=<name>`: creates the PDF printer `<name>`
    (`scripts/create_printer.sh`) and streams every PDF printed on it to
    the socket (`file-begin`, `file-chunk`..., `file-end`), then deletes it
  - `POST /api/vnc/file`: called by `scripts/postprocess.sh` after cups-pdf
    wrote a PDF; only accepted from inside the container
- **sshd**: the backend logs in as root with the host's `/root/.ssh/id_rsa`
  (key only, root has no password) to create printers

## How it is used

- Container **`daas-0-extensions`** from image **`daas-0-extensions`**.
- The **DaaS backend starts it** on its own start and stops it on its stop
  (`[service_containers]` in `src/config/container.toml`), with ports
  631, 8010 (and 8020, unused) published on `127.0.0.1`.
- Settings in `src/config/extensions.toml`: printer name prefix
  (`printer` + user id), ports, display name of the printer in the
  instances (`design-printer`).
- When a user opens a session, the backend creates `printer<user id>`
  here, adds `design-printer` (IPP to this container) in the instance, and
  connects the websocket to pass PDFs on to the browser.

## Commands

From `installer/` (normal use):

```bash
make extensions-install     # build the image; a running daas-0-extensions is restarted from it
make extensions-status      # running / stopped / not installed
make extensions-logs        # follow the log (printer connections, files)
make extensions-restart
make extensions-reinstall   # delete + build + start
make extensions-delete      # stop it and remove the image
```

Restarting removes all printers and pending PDFs (no volume); the backend
creates the printers again with the next session.

From `installer/extensions/` (working on the image itself), as root:

| Command | What it does |
|---|---|
| `make build` | Copies the host's ssh public key into `VNCService/` and builds `daas-0-extensions` |
| `make check` | Starts a test container `daas-0-extensions-test` (no published ports), checks node, cupsd, sshd and CUPS, prints a test page end to end like the backend (websocket → printer → PDF back over the websocket), and checks that a printer id cannot run shell commands and the file API cannot send/delete other files. Removes it again |
| `make clean` | Removes the image and the copied key |

## Things to know

- **Security**: the instances can reach this container directly on the
  docker bridge, and users have a terminal there. So `server.js` only
  accepts printer ids of `A-Z a-z 0-9 _ -` (they never reach a shell) and
  the file API only PDFs in a printer folder, only from inside the
  container. Both are covered by `make check`.
- CUPS (631) is open to every address incl. its admin pages; that is how
  the instances print. Never publish 631 on a public address.
- cups-pdf sometimes passes a broken byte in the PDF name to the
  post-processing hook; `postprocess.sh` looks the file up by its job number.
- Port 8020 in `container.toml` is a leftover of the old audio server and
  can be removed.

## Files

| File | Content |
|---|---|
| `VNCService/Dockerfile` | The image |
| `VNCService/server.js` | Printer websocket + file API |
| `VNCService/scripts/create_printer.sh` | Creates the cups-pdf printer of a user |
| `VNCService/scripts/delete_printer.sh` | Removes it (not called automatically) |
| `VNCService/scripts/postprocess.sh` | cups-pdf hook: reports a new PDF to `server.js` |
| `VNCService/scripts/cupsd.conf` | CUPS config |
| `check.bash` | Smoke test behind `make check` |
| `Makefile` | build, check, clean |
| `Backend/`, `webapp/` | Prototype from the original printer/microphone work (a Node control backend and a React test page). Not built, not used by DaaS |
