# Design

This project focuses on a novel approach to Desktop-as-a-Service (DaaS) solutions,
enabling seamless deployment of unmodified Linux and Windows desktop applications.
Unlike traditional methods, this solution allows users
to interact with applications entirely through a browser,
eliminating the need for additional client software.
The contained source code was created during a research project
and represents a prototypic state of implementation.
It still contains some rough edges,
so be warned and don't use it in productive environments!

______________________________________________________________________

## Table of Contents

1. [Features](#features)
2. [Installation: from a fresh Debian 12 to a running system](#installation-from-a-fresh-debian-12-to-a-running-system)
   1. [Starting point](#1-starting-point)
   2. [Log in as root and install git + make](#2-log-in-as-root-and-install-git--make)
   3. [Get the three repositories](#3-get-the-three-repositories)
   4. [Write the settings file](#4-write-the-settings-file)
   5. [Run the installer](#5-run-the-installer)
   6. [Check the installation](#6-check-the-installation)
   7. [Prepare the computer with the browser](#7-prepare-the-computer-with-the-browser)
   8. [First login](#8-first-login)
   9. [Optional: run the end-to-end tests](#9-optional-run-the-end-to-end-tests)
3. [Usage](#usage)
4. [Acknowledgments](#acknowledgments)
5. [Resources](#resources)

______________________________________________________________________

## Features

- Enables deployment of unmodified Linux and Windows applications
- Integration of Virtual Machines and Containers (by using Proxmox and Docker)
- Browser-based user interaction (by using Guacamole as a Desktop Gateway)
- Dedicated user frontend [Repo: Frontend](https://github.com/design-daas-fra-uas/design-daas-application-frontend)
- Dedicated authentication backend [Repo: Backend](https://github.com/design-daas-fra-uas/design-daas-backend-java)
- End-to-end tests of the whole system with Playwright [Repo: E2E](https://github.com/design-daas-fra-uas/design-daas-e2e)

## Installation: from a fresh Debian 12 to a running system

This section starts with a freshly installed Debian 12 and ends with the admin
logged in to the web frontend. Follow it from top to bottom and type every
command exactly as shown; values in `<angle brackets>` are yours to fill in.

Everything runs on **one host**. Users only ever open one address, the
frontend:

| Part | What it is | Do users open it? |
|---|---|---|
| **Frontend** | Web app users and admins work in (`frontend.service`) | **Yes: `https://<host>:8443`**, the only address |
| DaaS backend | Python API that creates and controls the desktops (`daas.service`, `127.0.0.1:5000`) | No |
| auth service | Java service for users, login and permissions (`daas-auth.service`, `127.0.0.1:8080`) | No |
| Proxmox VE | Runs the virtual machines | No |
| Containers | `guacd` (desktop gateway), RabbitMQ, PostgreSQL, `extensions`, and one container per started desktop | No |

`<host>` is the host's full name, `<HOST_NAME>.<HOST_DOMAIN>` from step 4,
e.g. `pve1.daas-design.de`. In the background the frontend also uses port
**443** of the same name (DaaS API and the desktop stream), so ports 8443 and
443 of the host must be reachable from the users' computers.

### 1. Starting point

**The host** (the computer the system is installed on):

- **Debian 12 "bookworm"**, amd64, freshly installed. No other version: Proxmox
  VE 8 is built for Debian 12. During the Debian installation:
  - set a **root password** (do not leave it empty),
  - in the software selection, choose **SSH server** and **standard system
    utilities**, and no desktop environment.
- Hardware virtualization (Intel VT-x / AMD-V) **enabled in the BIOS/UEFI**
  (for a VM: nested virtualization), at least 4 CPU cores, 16 GB RAM and
  250 GB disk (the install ISOs take about 30 GB, the docker images about
  20 GB, the rest is for the VM disks).
- Internet access and an IPv4 address that **never changes** (static, or a
  DHCP reservation in the router): the installer writes it into
  `/etc/hosts`, and Proxmox stops working when it changes.
- **Network: a wired connection is the simplest.** Proxmox takes over the
  network configuration (`/etc/network/interfaces`), and a Wi-Fi set up by
  the Debian installer would be gone after the installer's reboot. A Wi-Fi
  only works if **NetworkManager** runs it; the installer checks this and
  stops before changing anything if it does not (see below).

**Only if the host uses Wi-Fi:** hand the Wi-Fi to NetworkManager before step
2. Do this at the host's console, not over SSH: the connection drops for a
moment. As root (`su -`), with your Wi-Fi device (`ip -br link`, e.g.
`wlp3s0`) and network:

```bash
apt-get install -y network-manager
ifdown wlp3s0
nano /etc/network/interfaces     # put a # in front of every line of the wlp3s0 block (allow-hotplug, iface, wpa-ssid, wpa-psk)
systemctl restart NetworkManager
nmcli device wifi connect "<SSID>" password "<Wi-Fi password>"
nmcli device                      # wlp3s0 must show "connected"
```

The installer then keeps the Wi-Fi working through Proxmox's changes.

**The client**: a second computer with Debian and Firefox or Chromium in the
same network. This is where you (and later the users) open the frontend.

**Time**: about 1–2 hours, most of it unattended. The Windows ISOs alone
download about 11 GB from Microsoft.

### 2. Log in as root and install git + make

Every command on the host runs **as root**. Log in as `root` at the host's
console, or from the client over SSH with the normal user created during the
Debian installation and switch to root:

```bash
su -
```

Type `su -` with the dash: without it `/usr/sbin` is missing from the `PATH`
and several tools are not found. (Debian does not accept `ssh root@...` with
a password, hence the detour over the normal user.)

Install the two tools the installer needs to start; it installs everything
else itself (Proxmox, docker, nginx, Python, ...):

```bash
apt-get update
apt-get install -y git make
```

### 3. Get the three repositories

The system consists of three repositories that must be cloned **next to each
other** in the same folder. This guide uses `/daas`, so every path below
can be copied as it is:

```bash
mkdir -p /daas
cd /daas
git clone https://github.com/design-daas-fra-uas/design-daas.git
git clone https://github.com/design-daas-fra-uas/design-daas-application-frontend.git
git clone https://github.com/design-daas-fra-uas/design-daas-backend-java.git
```

Afterwards `/daas` contains:

```
/daas/design-daas                        this repository: DaaS backend + installer
/daas/design-daas-application-frontend   frontend
/daas/design-daas-backend-java           auth service
```

The installer builds the frontend and the auth service from these folders;
you do not install them yourself. Any other folder works the same way, as
long as the three repositories are next to each other: then replace
`/daas` in all commands. The installer writes the folder into the
services when it installs them, so do not move it afterwards (or run
`make reinstall` after moving it).

### 4. Write the settings file

All settings of the system are in one file, `installer/daas.env`. First find
out the host's network interface, IP address and name:

```bash
ip -br -4 addr
hostname
```

Example output of `ip -br -4 addr`: `enp0s3  UP  192.168.0.158/24`. The
interface is `enp0s3`, the IP is `192.168.0.158` (without the `/24`).

Create the settings file and open it:

```bash
cd /daas/design-daas/installer
make env
nano daas.env
```

`make env` copies the template `daas.env.example` to `daas.env` (readable by
root only, never committed). Set these keys; every key is also explained in
the file itself:

| Key | Value |
|---|---|
| `HOST_NAME` | the short host name, e.g. `pve1` (the output of `hostname`) |
| `HOST_DOMAIN` | a domain, e.g. `daas-design.de` (it does not need to exist in public DNS) |
| `HOST_IP` | the IP address, e.g. `192.168.0.158` |
| `NET_DEVICE` | the network interface, e.g. `enp0s3` |
| `STANDALONE` | `yes` (one host, the normal case) |
| `HOST_NUMBER` | keep `11` |
| `ADMIN_EMAIL` | e-mail address of the first admin; you log in with it |
| `ADMIN_PASSWORD` | password of that admin |
| `AUTH_DB_PASSWORD`, `DAAS_DB_PASSWORD`, `PVE_API_PASSWORD` | three different new passwords; only used internally, you never type them in |

Leave all other keys as they are. In particular leave `DAAS_PUBLIC_URL`,
`FRONTEND_PUBLIC_URL` and `AUTH_PUBLIC_URL` **empty**: then the frontend is
`https://<HOST_NAME>.<HOST_DOMAIN>:8443` and everything else follows that
name.

Every value that still starts with `change-me-` must be replaced.

`daas.env` is the **only file you edit**. The installer writes every other
settings file from it (`installer/auth/.env`, `installer/frontend/.env`,
`src/config/local/*.toml`) and overwrites them on the next run, so changes
there are lost. To change a setting later, edit `daas.env` and see
[installer/README.md → Which files do I edit?](installer/README.md#which-files-do-i-edit)
for the command that applies it.

### 5. Run the installer

```bash
cd /daas/design-daas/installer
make install
```

On a fresh Debian the first run installs the Proxmox kernel and **stops on
purpose** with `Phase 1 done. Reboot into the PVE kernel, then run this
again.` Reboot:

```bash
reboot
```

Log in as root again (step 2) and run the same command a second time:

```bash
cd /daas/design-daas/installer
make install
```

The second run goes through all seven steps. Each one starts with a banner
such as `==== [4/7] Docker images ====`:

| Step | What it does |
|---|---|
| 1/7 Proxmox VE | Proxmox repository + kernel (first run), then Proxmox VE itself (second run) |
| 2/7 Host dependencies | docker, docker-compose, nginx, dnsmasq, Python, ISO tools, an SSH key for root |
| 3/7 DaaS backend | Python environment, `daas.service`, configuration from `daas.env`, nginx, TLS certificate, DHCP for the desktops |
| 4/7 Docker images | service containers (guacd, RabbitMQ, PostgreSQL, extensions) and desktop images (x11vnc, wine) |
| 5/7 auth service | builds and starts it, creates the admin account and checks that it can log in |
| 6/7 Frontend + start | builds and starts the frontend, starts the DaaS backend |
| 7/7 ISOs | builds the unattended install ISOs for Debian 12, Windows 10 and Windows 11 and uploads them to Proxmox (the longest step) |

At the end it prints `Everything installed. Check with: make status` and the
line for the client's hosts file (step 7).

**If a step fails:** the message says what is wrong; the full log is
`/var/log/daas-installer.log`. Fix the cause and run `make install` again:
every step can be repeated and skips what is already done. To install
without the ISOs first, run `make install SKIP_ISOS=1`, and `make iso-install`
later.

### 6. Check the installation

```bash
make status
```

prints one line per component. All of them must be `active`, `running`,
`installed` or `built`. (After `make install SKIP_ISOS=1` the ISOs are `not
built` until `make iso-install`.)

These commands also test the running system the way a client does; they
change nothing and must each end with `RESULT: all checks passed`:

```bash
make proxmox-check
make daas-check
make auth-check
make frontend-check
```

### 7. Prepare the computer with the browser

All commands in this step run **on the client**.

**a) Make the host name known.** Print the line for the client's hosts file
**on the host**:

```bash
make -C /daas/design-daas/installer client-hosts
```

It is e.g. `192.168.0.158  pve1.daas-design.de`. Unless your DNS already
resolves the name, add it on the client as root (`su -`), with your line:

```bash
echo "192.168.0.158  pve1.daas-design.de" >> /etc/hosts
```

**b) Trust the system's certificate.** The installer creates its own
certificate authority (CA). Copy it to the client:

```bash
scp <user>@<host-ip>:/etc/nginx/ssl/daas-ca.crt ~/
```

and import `~/daas-ca.crt` into the browser once:

- **Firefox:** *Settings → Privacy & Security → Certificates → View
  Certificates… → Authorities → Import…*, select the file, tick *Trust this CA
  to identify websites*, *OK*.
- **Chromium:** it reads its certificates from your user's NSS database.
  Install the tool once as root (`apt-get install -y libnss3-tools`), then, as
  your normal user:

  ```bash
  mkdir -p ~/.pki/nssdb
  [ -f ~/.pki/nssdb/cert9.db ] || certutil -d sql:$HOME/.pki/nssdb -N --empty-password
  certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n daas-ca -i ~/daas-ca.crt
  ```

Restart the browser afterwards. This import is **required**: without it the
frontend cannot reach the system's backend in the background, and the
dashboard and the desktops stay empty.

### 8. First login

Open **`https://<host>:8443/`** (e.g. `https://pve1.daas-design.de:8443/`),
choose the *Admin* tab and log in with `ADMIN_EMAIL` / `ADMIN_PASSWORD` from
`daas.env`. Open *System status* in the admin menu: every part (backend, auth
service, containers, frontend) must be green.

The installation is complete. Everything else about the installer (single
steps, rebuilding after code changes, uninstalling, changing passwords,
troubleshooting) is in [installer/README.md](installer/README.md).

### 9. Optional: run the end-to-end tests

The repository [design-daas-e2e](https://github.com/design-daas-fra-uas/design-daas-e2e)
tests the installed system through the browser (124 Playwright tests: login,
user dashboard, permissions, limits, desktops, system status, Docker,
logout). It installs nothing itself; its README describes how to set it up on
the host or the client and run it against this installation.

## Usage

Users and admins work only in the frontend, `https://<host>:8443/`; no client
software is needed. The login page has two tabs, *User* and *Admin*.

### On the host

The installer sets up three systemd services: `daas-auth` (auth service),
`daas` (DaaS backend; it also starts and stops the service containers) and
`frontend`. Control them as root with `make`:

```bash
make -C /daas/design-daas/installer status
make -C /daas/design-daas/installer restart
make -C /daas/design-daas/installer logs
```

`start`, `stop` and `<component>-logs` (e.g. `make auth-logs`) work the same
way; the complete list is in [installer/README.md](installer/README.md).

- **API reference** of the DaaS backend: [docs/api.md](docs/api.md), generated
  from the route definitions (`make -C src api-docs`).
- **Logs**: every request carries an `X-Request-ID`, written into the logs of
  the frontend, the DaaS backend (`journalctl -u daas`, `src/data/logs/`) and
  the auth service. Search for that id to follow one action through all three.

## Acknowledgments

This work was funded by the Federal Ministry for Economic Affairs and Climate Action ("Bundesministerium 
für Wirtschaft und Klimaschutz") in the framework of the central innovation programme for small and medium-sized 
enterprises ("Zentrales Innovationsprogramm Mittelstand (ZIM)").

## Resources

- [Video: Usage](https://www.youtube.com/watch?v=nZoH-ngyu9E)
- [Paper: Open Journal of Cloud Computing (OJCC)](https://www.ronpub.com/ojcc/OJCC_2023v8i1n01_Baun.html)
- [Paper: MobileWeb and Intelligent Information Systems (MobiWIS 2024)](https://link.springer.com/chapter/10.1007/978-3-031-68005-2_1)
- [Repo: Frontend](https://github.com/design-daas-fra-uas/design-daas-application-frontend)
- [Repo: Backend](https://github.com/design-daas-fra-uas/design-daas-backend-java)
