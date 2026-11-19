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

1. [Quick start](#quick-start)
2. [Features](#features)
3. [Installation: from a fresh Debian 12 to a running system](#installation-from-a-fresh-debian-12-to-a-running-system)
   1. [Starting point](#1-starting-point)
   2. [Log in as root and install git + make](#2-log-in-as-root-and-install-git--make)
   3. [Get the three repositories](#3-get-the-three-repositories)
   4. [Write the settings file](#4-write-the-settings-file)
   5. [Run the installer](#5-run-the-installer)
   6. [Check the installation](#6-check-the-installation)
   7. [Trust the certificate in the browser](#7-trust-the-certificate-in-the-browser)
   8. [First login](#8-first-login)
   9. [Optional: run the end-to-end tests](#9-optional-run-the-end-to-end-tests)
4. [Usage](#usage)
5. [Troubleshooting](#troubleshooting)
6. [Acknowledgments](#acknowledgments)
7. [Resources](#resources)

______________________________________________________________________

## Quick start

Everything runs on **one computer**: install it there and open it in the
browser on the same computer. Every step links to the full explanation further
down. **Only on "Debian 12 "bookworm". No other version: Proxmox VE 8 is built for Debian 12.**

**1. Get the code** ([details](#3-get-the-three-repositories))

```bash
su -
apt-get update && apt-get install -y git make
mkdir -p /daas && cd /daas
git clone https://github.com/design-daas-fra-uas/design-daas.git
git clone https://github.com/design-daas-fra-uas/design-daas-application-frontend.git
git clone https://github.com/design-daas-fra-uas/design-daas-backend-java.git
```

**2. Write the settings** ([details](#4-write-the-settings-file))

```bash
ip -br -4 addr      # your network device, e.g. enp0s3 or wlp3s0
cd /daas/design-daas/installer
make env
nano daas.env
```

Set `HOST_IP` and `NET_DEVICE` to that device and every `change-me-*` password. 
(Do not leave `HOST_IP` empty)

**3. Install** ([details](#5-run-the-installer))

```bash
make install        # first run stops: "Reboot into the PVE kernel"
reboot
# open a terminal again, su -
cd /daas/design-daas/installer
make install        # second run: 7 steps, 1-2 hours
make status         # every line: active / running / installed / built
```

**4. Open it** ([details](#7-trust-the-certificate-in-the-browser))

Import `/etc/nginx/ssl/daas-ca.crt` into the browser as a trusted
**certificate authority** and restart the browser. Then open:

| What | Address | Login |
|---|---|---|
| DaaS frontend | `https://pve1.daas-design.de:8443/` | *Admin* tab, `ADMIN_EMAIL` / `ADMIN_PASSWORD` |
| Proxmox | `https://pve1.daas-design.de:8006/` | `root`, realm *Linux PAM*, the root password |

(The name is `<HOST_NAME>.<HOST_DOMAIN>` from `daas.env`.)

Something went wrong? See [Troubleshooting](#troubleshooting).

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

Everything runs on **one host**, and you use it in the browser on that same
host. You open two addresses:

| Part | What it is | Do you open it? |
|---|---|---|
| **Frontend** | Web app users and admins work in (`frontend.service`) | **Yes: `https://<host>:8443`** |
| **Proxmox VE** | Runs the virtual machines | **Yes: `https://<host>:8006`** (admin only) |
| DaaS backend | Python API that creates and controls the desktops (`daas.service`, `127.0.0.1:5000`) | No |
| auth service | Java service for users, login and permissions (`daas-auth.service`, `127.0.0.1:8080`) | No |
| Containers | `guacd` (desktop gateway), RabbitMQ, PostgreSQL, `extensions`, and one container per started desktop | No |

`<host>` is the host's full name, `<HOST_NAME>.<HOST_DOMAIN>` from step 4,
e.g. `pve1.daas-design.de`. The installer adds this name to the host's
`/etc/hosts`, so the browser finds it without any DNS.

### 1. Starting point

- **Debian 12 "bookworm"**, amd64, freshly installed, with a desktop and a
  browser (e.g. GNOME with Firefox). No other version: Proxmox VE 8 is built
  for Debian 12.

**Time**: about 1–2 hours, most of it unattended. The Windows ISOs alone
download about 11 GB from Microsoft.

### 2. Log in as root and install git + make

Every command runs **as root**. Open a terminal and switch to root with
`su -` (it asks for the root password; use `su -`, not `sudo`):

```bash
su -
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
out the host's network interface and name:

```bash
ip -br -4 addr
hostname
```

Example output of `ip -br -4 addr`: `enp0s3  UP  192.168.0.158/24`. The
interface is `enp0s3`.

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
| `HOST_IP` | leave **empty**: the installer takes the IP the host uses for its network. If you set it, it must be one of the host's own addresses, or the install stops before changing anything |
| `NET_DEVICE` | the network interface, e.g. `enp0s3` |
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
there are lost. To change a setting later, edit `daas.env`.

### 5. Run the installer

```bash
cd /daas/design-daas/installer
make install
```

It first prints the IP it uses, e.g. `HOST_IP: 192.168.0.158`. On a fresh
Debian the first run then installs the Proxmox kernel and **stops on
purpose** with `Phase 1 done. Reboot into the PVE kernel, then run this
again.` Reboot:

```bash
reboot
```

Open a root terminal again (step 2) and run the same command a second time:

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
address to open.

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

These commands also test the running system the way the browser uses it;
they change nothing and must each end with `RESULT: all checks passed`:

```bash
make proxmox-check
make daas-check
make auth-check
make frontend-check
```

### 7. Trust the certificate in the browser

The installer creates its own certificate authority (CA),
`/etc/nginx/ssl/daas-ca.crt`. Import it into the browser once:

- **Firefox:** *Settings → Privacy & Security → Certificates → View
  Certificates… → Authorities → Import…*, select
  `/etc/nginx/ssl/daas-ca.crt`, tick *Trust this CA to identify websites*,
  *OK*.

Restart the browser afterwards. This import is **required**: without it the
frontend cannot reach the system's backend in the background, and the
dashboard and the desktops stay empty.

### 8. First login

Open **`https://<host>:8443/`** (e.g. `https://pve1.daas-design.de:8443/`),
choose the *Admin* tab and log in with `ADMIN_EMAIL` / `ADMIN_PASSWORD` from
`daas.env`. Open *System status* in the admin menu: every part (backend, auth
service, containers, frontend) must be green.

Proxmox is at **`https://<host>:8006/`**: log in as `root`, realm *Linux PAM
standard authentication*, with the root password.

The installation is complete. Everything else about the installer (single
steps, rebuilding after code changes, uninstalling, changing passwords,
troubleshooting) is in [installer/README.md](installer/README.md).

### 9. Optional: run the end-to-end tests

The repository [design-daas-e2e](https://github.com/design-daas-fra-uas/design-daas-e2e)
tests the installed system through the browser (124 Playwright tests: login,
user dashboard, permissions, limits, desktops, system status, Docker,
logout). It installs nothing itself; its README describes how to set it up on
the host and run it against this installation.

## Usage

Users and admins work only in the frontend, `https://<host>:8443/`; no client
software is needed. The login page has two tabs, *User* and *Admin*. The
virtual machines can also be seen and managed in Proxmox,
`https://<host>:8006/`.

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

## Troubleshooting

**First, where do I look?** (as root)

```bash
make -C /daas/design-daas/installer status            # which part is not running
tail -n 50 /var/log/daas-installer.log                # what the installer did last
make -C /daas/design-daas/installer auth-logs         # logs of one part: auth-, daas-, frontend-, db-, guacd-...
```

If an installer step failed, fix the cause and run `make install` again. Every
step can be repeated and skips what is already done.

### Commands and permissions

- **`<user> is not in the sudoers file`**: use `su -` instead of `sudo` (it
  asks for the **root** password), or run a single command with
  `su -c '<command>'`.
- **`command not found`** for tools like `ip`, `reboot` or `qm`: you switched
  with `su` instead of `su -`. With the dash, `/usr/sbin` is in the `PATH`.
- **`Permission denied`** on files in `/daas`, or git says **`detected dubious
  ownership in repository`**: the repositories belong to root (they were
  cloned as root), and you are working as your normal user. Either work as
  root, or give the folder to your user once. The installer still runs as
  root afterwards:

  ```bash
  su -c 'chown -R <user>:<user> /daas'
  ```

### `HOST_IP ... is not an address of this host`

`make install` stops with this before it changes anything: `HOST_IP` in
`daas.env` is set to an address this computer does not have (copied from
another machine or an example). Leave it **empty** (`HOST_IP=`) and run
`make install` again; the installer then detects it.

### The browser cannot open the frontend or Proxmox

1. **The host's IP changed** after the install (after a reboot or a router
   restart, with DHCP or Wi-Fi). Compare:

   ```bash
   getent hosts <HOST_NAME>.<HOST_DOMAIN>    # the IP in /etc/hosts ...
   ip -br -4 addr                            # ... must be one of these
   ```

   If not, put the new IP in front of the name in `/etc/hosts` and restart
   Proxmox:

   ```bash
   nano /etc/hosts                          # <new IP> <HOST_NAME>.<HOST_DOMAIN> <HOST_NAME>
   systemctl restart pve-cluster pveproxy
   ```

   To prevent it, give the host a static IP or a DHCP reservation in the
   router.
2. **A part is not running**: see
   [below](#a-part-shows-as-not-running-in-make-status).
3. **Check without the browser.** `curl -kI https://<host>:8443/` must answer
   `HTTP/1.1 200`. If it does and the browser still fails, the problem is in
   the browser: see the next section.

### The page opens but warns about the certificate, or stays empty

The system's certificate authority is not imported into the browser, or the
browser was not restarted afterwards. Import `/etc/nginx/ssl/daas-ca.crt` as
an **authority** (not as a website certificate), see
[step 7](#7-trust-the-certificate-in-the-browser). Clicking "accept the
risk" is not enough: the frontend also talks to port 443 in the background,
and that connection fails silently.

### A part shows as not running in `make status`

```bash
make -C /daas/design-daas/installer <part>-logs      # e.g. daas-logs, db-logs
make -C /daas/design-daas/installer <part>-restart
```

`make help` lists every part and action. More installer-specific problems
(Proxmox kernel, Wi-Fi, enterprise repository) are in
[installer/README.md → Troubleshooting](installer/README.md#troubleshooting).

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
