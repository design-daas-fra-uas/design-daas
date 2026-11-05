# iso: unattended install ISOs for DaaS VMs

Builds install ISOs that set up a VM **without any clicks**: the OS
installs itself, then a post-install script adds the desktop, the DaaS
agent and ssh access for the backend. The backend creates VMs from them
(Proxmox storage `daas-iso`).

| ISO | Status | Source |
|---|---|---|
| `debian12-daas.iso` | **Built by `make install`** (step 7) | Debian 12 netinst, downloaded automatically |
| `win10-daas.iso` | **Built by `make install`** (step 7) | Windows 10 22H2 Enterprise Evaluation, German, downloaded automatically |
| `win11-daas.iso` | **Built by `make install`** (step 7) | Windows 11 24H2 Enterprise Evaluation, English UI with German keyboard/formats, downloaded automatically |

## What a VM gets

**Debian 12** (`cfg/debian12`, preseed + `postinstall/`):

- unattended install (`preseed.cfg`), host name `debian-unattend`
- X with the qtile window manager, kitty, galculator, pulseaudio with the
  virtual speaker/microphone, ceph client (no browser)
- the DaaS agent (`src/app/daas/messaging` + `src/app/inst`, copied at
  build time)
- ssh: `sshd_config` and **only the host's public key** as
  `/root/.ssh/authorized_keys`, so the backend can log in

**Windows** (`cfg/win10`, `cfg/win11`, `autounattend.xml` + `postinstall/`):
virtio drivers, Python, Firefox, TightVNC, winget, Ceph + Dokany (shared
folders), PsTools, the DaaS agent and OpenSSH with the host's public key.

## How it is used

`make install` in `installer/` runs `iso-install`:

```
proxmox-isogen    make -C iso install                     tools for the generators
                  make -C iso ISOTYPE=debian12 build check   for each of ISOTYPES
proxmox-isoupload copy iso/iso/<type>-daas.iso into the Proxmox storage daas-iso
```

`ISOTYPES` defaults to all three (`debian12 win10 win11`). Build only some
with e.g. `make iso-install ISOTYPES=debian12`.

## Commands

In `installer/iso/`, as root:

| Command | What it does |
|---|---|
| `make install` | Installs the tools the generators need (xorriso, syslinux, genisoimage, ...) |
| `make build ISOTYPE=debian12` | Builds `iso/debian12-daas.iso` (also `win10`, `win11`) |
| `make check ISOTYPE=debian12` | Checks a built ISO without booting it: readable, trusts exactly the host's current key, **contains no private key** |
| `make clean` | Removes the build folders in `out/`, keeps every ISO |
| `make clean-all` | Also removes the generated `*-daas.iso` |

Options: `USERNAME=root USERPASS=root` (the VM account), `ISOTYPE=...`.

### Windows ISOs

`scripts/generate-windows-iso.bash -v 10|11` (one script for both) downloads
Microsoft's **Enterprise Evaluation** ISO from its stable official link, once
(about 5.5 GB; an interrupted download continues on the next run, and the
ISO is checked before it is used):

| Type | Edition | Language |
|---|---|---|
| win10 | Windows 10 22H2 Enterprise Evaluation | German |
| win11 | Windows 11 24H2 Enterprise Evaluation | English UI (Microsoft's link has no German one); German keyboard and formats |

Evaluation means **90 days**, then Windows asks for activation: fine for
tests and demos, for real use you need licences (then put a matching ISO
and product key into the generator and `cfg/winNN/autounattend.xml`).
The answer files contain no product key; Windows 11 skips the TPM, Secure
Boot and RAM checks (`LabConfig`) so it installs in any VM.

The other Windows downloads (virtio, Python, ...) happen automatically into
`cfg/<type>/tools` and `cfg/<type>/env`, once; a failed download leaves no
file behind and stops the build.

Office is **not** installed (its line in `postinstall.bat` is commented
out). The old automatic download of an Office installer from file-hosting
links was removed; use a licensed Office Deployment Tool setup in
`cfg/<type>/tools/office/` if you need it.

### Test VM and dev cluster (optional)

| Command | What it does |
|---|---|
| `make disk` / `make start` / `make ssh` / `make stop` | Boot the built ISO in qemu on this host (ssh on `127.0.0.1:VMSSHPORT`) to try an install |
| `make build-cluster`, `disk-cluster`, `start-cluster`, `stop-cluster` | Three Proxmox nodes in qemu (`cfg/devenv`), for testing cluster setups. Uses its own throwaway key pair in `cfg/devenv/ssh`, never the host key |

## Security

- **Only public keys go into an ISO.** Before 2026-11-05 the generators
  copied the host's root *private* key into the ISOs and the VMs, which
  let any VM log in to the host as root. That key was rotated; the
  generators now copy `/root/.ssh/id_rsa.pub` only, and
  `make check` (run automatically by `iso-install`) fails if an ISO
  contains any private key.
- The VM account defaults to `root` / `root` (`USERPASS`). The backend
  logs in with the ssh key, not the password; set another password for
  anything beyond a lab.
- After rotating the host key, rebuild and re-upload the ISOs
  (`make iso-reinstall` in `installer/`): `make check` reports an ISO that
  still trusts an old key.

## Folders

| Path | Content |
|---|---|
| `Makefile`, `check.bash` | The commands above |
| `scripts/generate-windows-iso.bash` | Windows 10 and 11 (`-v 10|11`) |
| `scripts/generate-debian12-iso.bash`, `generate-devenv-iso.bash` | Debian ISO, dev cluster ISO |
| `scripts/vm-run.bash`, `vm-connect.bash`, `cluster-run.bash` | Test VM / dev cluster in qemu |
| `cfg/<type>/` | What goes into the ISO: unattended answers, post-install scripts, `ssh/sshd_config` |
| `iso/` | Downloaded sources and built `*-daas.iso` (not committed) |
| `out/` | Build folders (not committed) |
