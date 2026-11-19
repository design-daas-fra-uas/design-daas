# Developer tools

Tools for developing the DaaS system. **None of them is needed to install or
use it**: `make install` in `installer/` does not use this folder.

| Tool | What it is for |
|---|---|
| [`guacamole-client/`](guacamole-client/README.md) | Rebuilds `src/app/webroot/static/guacamole.js`, the remote-desktop client in the browser, from the Apache Guacamole sources (e.g. for another upstream version). The built file is committed. |
| `guac-sniff-deployment.sh` | Starts a separate Guacamole stack (postgres, guacd, web) to record the Guacamole protocol traffic against an `x11vnc` container, for analysing the protocol. Run `./guac-sniff-deployment.sh help`. |

More developer tools stay where they work, because they use the files there:

- `installer/iso/`: the **test VM** (`make disk` / `start` / `ssh` / `stop`,
  boots a built ISO in qemu) and the **dev cluster** (`make build-cluster`
  etc., three Proxmox nodes in qemu), see
  [installer/iso/README.md](../installer/iso/README.md).
- `installer/x11vnc/`, `installer/wine/`: `make run` / `shell` / `check` start a
  test container of a desktop image.
