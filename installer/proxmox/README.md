# proxmox: the host layer

Turns a fresh **Debian 12** into a **Proxmox VE 8** host (step 1 of
`make install`), and holds the optional Ceph/cluster setup and the ISO
upload. Proxmox runs the VMs; the DaaS backend drives it through its API
(`127.0.0.1:8006`) and creates the storages and bridges it needs itself.

## Install (step 1 of `make install`)

`make proxmox-install` (`install.bash`) needs **two runs with a reboot in
between**; `make install` does the first run, stops, and continues after
the reboot:

| Run | Kernel | What it does |
|---|---|---|
| 1 | Debian | Proxmox no-subscription repository, full upgrade, `proxmox-default-kernel`, host name and `/etc/hosts` (`HOST_NAME`, `HOST_DOMAIN`, `HOST_IP`). Then **reboot** |
| 2 | PVE | `proxmox-ve`, removes the Debian kernel, `update-grub` |

Both runs disable the **enterprise repositories** (they need a paid
subscription; without one `apt-get update` fails with 401 and stops `make
deps`). The files belong to Proxmox packages and may come back with
updates, so their lines are commented out, not deleted.

Everything else (docker, nginx, dnsmasq, ...) comes from `make deps`.
The storages `daas-iso`, `daas-img` and the bridges `vmbr0` (DaaS
network), `vmbr1` (instances), `vmbr8`, `vmbr9` are created by the DaaS
backend on every start (`src/config/vm.toml`).

## Commands

From `installer/`, as root:

| Command | What it does |
|---|---|
| `make proxmox-install` | The two runs above (`make install` skips it once Proxmox is installed) |
| `make proxmox-check` | Checks the host (changes nothing): PVE kernel and services, enterprise repository off and `apt-get update` working, storages `daas-iso`/`daas-img`, bridges `vmbr0`/`vmbr1` with the address from `HOST_NUMBER`, dnsmasq. Notes when a newer kernel waits for a reboot |
| `make proxmox-status` / `proxmox-logs` / `proxmox-restart` | The PVE services (`pve-cluster`, `pvedaemon`, `pveproxy`, ...) |
| `make proxmox-isogen` / `proxmox-isoupload` | Build the install ISOs / copy them into `daas-iso` (see `iso/README.md`) |

Restarting `pveproxy` (or the whole `proxmox` group) does not restart the
DaaS backend.

### Optional: Ceph and cluster (multi-host)

| Command | What it does |
|---|---|
| `make proxmox-install-ceph [CEPH_NETWORK=192.168.100.0/24] [CEPH_VERSION=reef]` | Ceph packages (no-subscription), network, monitor + manager. `reef` matches the Ceph client the Windows ISOs install; `squid` also works; `quincy` (the pveceph default) is end of life |
| `make proxmox-install-ceph-osd CEPH_DISK=/dev/vdb` | An OSD on an empty disk (**erases it**) |
| `make proxmox-install-ceph-cephfs` | MDS + standby and the CephFS `daasfs` |
| `make proxmox-install-ceph-pool` | RBD pool `daas-ceph`, added as storage |
| `make proxmox-cluster-create CLUSTER_NAME=... LINK_IP=...` | New cluster on this node |
| `make proxmox-cluster-join CLUSTER_IP=... LINK_IP=...` | Join a cluster (asks for the other node's root password) |

## Files

| File | Content |
|---|---|
| `install.bash` | The two install runs |
| `check.bash` | The test behind `make proxmox-check` |
| `ceph.bash` | Ceph actions (`-a ceph|osd|cephfs|pool`) |
| `cluster.bash` | Create (`-c`) or join (`-i`) a cluster |
| `isoupload.bash` | Copy ISOs into a Proxmox storage |

## Things to know

- Kernel updates arrive through `proxmox-default-kernel`; they are only
  used after a reboot. `make proxmox-check` notes when one is waiting.
- The backend creates bridges only when they are missing: after changing
  `HOST_NUMBER`, fix the existing addresses in `/etc/network/interfaces`
  (`proxmox-check` and `daas-configure` warn about a mismatch).
