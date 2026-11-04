# guacamole-client: the browser side of the remote desktop

Builds **`guacamole.js`**, the Apache Guacamole JavaScript client. The DaaS
viewer page loads it (`src/app/webroot/templates/layout-viewer.html` →
`/static/guacamole.js`) to show an instance's desktop in the browser: it
draws the screen and sends keyboard, mouse and audio over a websocket to
the DaaS backend, which forwards the Guacamole protocol to **guacd**.

```
browser (guacamole.js) ⇄ websocket ⇄ DaaS backend ⇄ guacd ⇄ VNC/RDP of the instance
```

## Do I need to run this?

**No, not for an installation.** The built file is committed as
`src/app/webroot/static/guacamole.js`, and `make install` in `installer/`
does not use this folder. Run it only to:

- verify the committed file (`make check`), or
- update the Guacamole client to another upstream version.

## Which version

- Upstream `apache/guacamole-client`, commit
  [`940c7ad`](https://github.com/apache/guacamole-client/commit/940c7ad37aefc06cb42c764a1deb6abab86f8290)
  ("Merge 1.5.3 changes back to master", 2023-06-22), with
  `Guacamole.API_VERSION` set to `1.5.3`.
- The backend's protocol code (`src/app/daas/proxy/handshake.py`,
  `syntax.py`) links to the same commit.
- guacd is built from guacamole-server **1.5.4**; the 1.5.x client and
  server speak the same protocol.
- Why not simply the 1.5.4 release: it is older code than this master
  commit and lacks `Guacamole.Client.State`, which the viewer uses.

The upstream build of this file is nothing more than all
`guacamole-common-js/src/main/webapp/{common,modules}/*.js` files in one
file, so `cat` is enough (no Maven/Java needed).

## Commands

In `installer/guacamole-client/` (no root needed, needs curl + internet):

| Command | What it does |
|---|---|
| `make build` | Downloads the JavaScript sources of `GUAC_REF` once (into `upstream/`) and builds `guacamole.js` here |
| `make check` | Builds and compares with the committed `src/app/webroot/static/guacamole.js`: `OK` when identical |
| `make install` | Builds and copies `guacamole.js` to `src/app/webroot/static/` |
| `make clean` | Removes `upstream/` and the build |

Update to another upstream version, e.g. the 1.6.0 release:

```bash
make install GUAC_REF=1.6.0 GUAC_API_VERSION=1.6.0
git diff --stat ../../src/app/webroot/static/guacamole.js
make -C .. daas-restart        # then reload the viewer page and test a session
```

`GUAC_REF` can be a tag (`1.6.0`) or a commit id. **Not every version
works:** the viewer (`src/app/webroot/static/viewer_guac.js`) uses
`Guacamole.Client.State`, which exists on master since 2023 and in 1.6.0,
but **not in the 1.5.x releases** (1.5.4, 1.5.5): with those the viewer
breaks. After an update, also update the commit links in
`src/app/daas/proxy/` and this README, and test a desktop session (screen,
keyboard, mouse, sound) before committing. `make install` with the default
`GUAC_REF` restores the current file.

## Things to know

- A failed download or build never leaves a broken `guacamole.js`: the
  file is written to a temp file and moved into place at the end.
- The extensions webapp (`installer/extensions/webapp`) has its own copy of
  the client from npm (`guacamole-common-js` 1.5.0); this folder does not
  change it.
- Earlier this folder used a git submodule (`upstream/`); its `.gitmodules`
  entry pointed to an old path and never worked in this repo layout, so it
  was replaced by the pinned download.

## Files

| File | Content |
|---|---|
| `Makefile` | build, check, install, clean |
| `upstream/`, `guacamole.js` | Downloaded / built by the Makefile, not committed |
