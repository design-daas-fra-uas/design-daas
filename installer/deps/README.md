# deps: host dependencies

Step 2 of `make install` (`make deps`, as root, after Proxmox is installed):
everything the other steps need on the host, in one place. The other
scripts only check for their tools (`require_cmds`) and never install
packages; a missing tool tells you to run `make deps`.

## What it installs

| Group | Packages | Needed by |
|---|---|---|
| Base | ca-certificates curl wget git jq openssl rsync parallel openssh-client isc-dhcp-client | all scripts, `src/Makefile`, `dhclient` for `STANDALONE` |
| Python | python3-pip python3.11-venv python3.11-dev python3-click build-essential | the backend's venv (`daas-install`) |
| Host | docker.io nginx dnsmasq | containers, the two nginx sites, DHCP for the VMs |
| ISO | syslinux syslinux-utils isolinux xorriso genisoimage unzip unrar-free | `iso-install` |

Plus:

- **docker**: data root `/home/daas-docker` (`/etc/docker/daemon.json`).
  Docker is only restarted when that file changes or docker is not
  running, because a restart stops every container (service containers,
  user instances, Java backend, frontend).
- **docker-compose v2.24.0** (`/usr/bin/docker-compose`, used by the Java
  backend and the frontend), checked against its pinned sha256 before it
  is installed.
- **root's SSH key** `/root/.ssh/id_rsa`, created once (or its mode fixed
  to 600). The backend logs in to instances, VMs and the extensions
  container with it; only its public key goes into images and ISOs.

## Running it again

Safe at any time: installed packages are kept (nothing is upgraded),
docker keeps running when its config did not change, docker-compose and
the key are kept.

If it stops at `apt-get update`, one of the package sources fails. On a
Proxmox host without subscription that is usually the enterprise
repository: `make proxmox-check` shows it, `proxmox/README.md` explains it.

## Files

| File | Content |
|---|---|
| `install.bash` | The step above |
