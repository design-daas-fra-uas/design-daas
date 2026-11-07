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

- Upstream `apache/guacamole-client` release **1.6.0**
  (`GUAC_REF` in the Makefile), the same version as guacd.
- The viewer (`src/app/webroot/static/viewer_guac.js`) uses
  `Guacamole.Client.State`: it exists in 1.6.0 and on master since 2023,
  but **not in the 1.5.x releases** (with those the viewer breaks).
- guacd 1.6.0 still speaks protocol `VERSION_1_5_0`, so the backend's
  protocol code (`src/app/daas/proxy/`) works unchanged.
- Until 2026-11-05 this was master commit `940c7ad` (after 1.5.3);
  `make install GUAC_REF=940c7ad37aefc06cb42c764a1deb6abab86f8290 GUAC_API_VERSION=1.5.3`
  restores that file.

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

Update to another upstream version:

```bash
make install GUAC_REF=<tag> GUAC_API_VERSION=<version>
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
- Earlier this folder used a git submodule (`upstream/`); its `.gitmodules`
  entry pointed to an old path and never worked in this repo layout, so it
  was replaced by the pinned download.

## Files

| File | Content |
|---|---|
| `Makefile` | build, check, install, clean |
| `upstream/`, `guacamole.js` | Downloaded / built by the Makefile, not committed |
