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
2. [Installation](#installation)
3. [Usage](#usage)
4. [Acknowledgments](#acknowledgments)
5. [Resources](#resources)

______________________________________________________________________

## Features

- Enables deployment of unmodified Linux and Windows applications
- Integration of Virtual Machines and Containers (by using Proxmox and Docker)
- Browser-based user interaction (by using Guacamole as a Desktop Gateway)
- Dedicated user frontend [Repo: Frontend](https://github.com/nuromedia/design-daas-application-frontend)
- Dedicated authentication backend [Repo: Backend](https://github.com/nuromedia/design-daas-application-backend)

## Installation

The installation depends on Debian12 and several additional components and libraries.
A Makefile with all installation steps is provided in the "installer" folder.
Use it to install all components seperately.

- [Video: Installation](https://www.youtube.com/watch?v=-AUCHX9SRKE)

### Prerequisites

#### Supported Operating Systems (Host)

- Debian12

#### Utilized Libraries and Tools

- Guacamole
- Proxmox
- qemu-kvm
- docker.io
- Python 3.11+

#### Clone the repository

```bash
git clone git@github.com:nuromedia/design-daas.git
```

#### Install everything

Clone the frontend and the Java backend repositories next to this one, then
as root:

```bash
cd design-daas/installer
make env            # creates installer/daas.env: set host name, IP and passwords there
make install        # stops after the Proxmox kernel on a fresh Debian:
reboot
make install        # run it again after the reboot
make status
```

`make install` runs every step in order: Proxmox, host dependencies, DaaS
backend, Docker images, Java backend, frontend, ISOs. What each step does,
what you get and all other `make` commands are described in
[installer/README.md](installer/README.md).

## Usage

The installer creates systemd targets for daas nginx and the frontend.
Use systemctl or comparable alternatives to control them.
By default, nginx is used as a proxy to host the daas application on the default port 443 and the frontend on 8443.
Both are reachable by using any modern web browser.

- [Video: Usage](https://www.youtube.com/watch?v=nZoH-ngyu9E)

```bash
make -C installer status
make -C installer restart   # java, daas, frontend
make -C installer logs
```

## Acknowledgments

This work was funded by the Federal Ministry
for Economic Affairs and Climate Action
("Bundesministerium für Wirtschaft und Klimaschutz")
in the framework of the central innovation programme
for small and medium-sized enterprises ("Zentrales
Innovationsprogramm Mittelstand (ZIM)").

## Resources

- [Video: Installation](https://www.youtube.com/watch?v=-AUCHX9SRKE)
- [Video: Usage](https://www.youtube.com/watch?v=nZoH-ngyu9E)
- [Paper: Open Journal of Cloud Computing (OJCC)](https://www.ronpub.com/ojcc/OJCC_2023v8i1n01_Baun.html)
- [Paper: MobileWeb and Intelligent Information Systems (MobiWIS 2024)](https://link.springer.com/chapter/10.1007/978-3-031-68005-2_1)
- [Repo: Frontend](https://github.com/nuromedia/design-daas-application-frontend)
- [Repo: Backend](https://github.com/nuromedia/design-daas-application-backend)
