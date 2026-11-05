SHELL := /bin/bash

# ============================================================
# Configuration
# ============================================================

DESIGN_FOLDER := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

# Stack settings shared by DaaS, frontend and auth service
# (copy daas.env.example to daas.env, or `make env`)
ENV_FILE ?= $(DESIGN_FOLDER)/installer/daas.env
# env_get KEY: value of KEY in ENV_FILE (empty if unset). Read with sed instead
# of `include` so values with $ or quotes are not mangled by make.
env_get = $(shell [ -f "$(ENV_FILE)" ] && sed -n 's/^$(1)=//p' "$(ENV_FILE)" 2>/dev/null | tail -n1 | sed -e 's/^"\(.*\)"$$/\1/' -e "s/^'\(.*\)'$$/\1/")
# -e <file> for the scripts when the env file exists
ENV_OPT = $(if $(wildcard $(ENV_FILE)),-e "$(ENV_FILE)")

FRONTEND_FOLDER ?= $(or $(call env_get,FRONTEND_FOLDER),$(abspath $(DESIGN_FOLDER)/../design-daas-application-frontend))

ISODIR := iso/iso
# ISOs built by iso-install. Windows needs a manually downloaded Windows ISO
# (iso/README.md): ISOTYPES="debian12 win10 win11"
ISOTYPES ?= debian12

# Host configuration: command line > environment > ENV_FILE > default
HOST_NUMBER ?= $(or $(call env_get,HOST_NUMBER),11)
HOST_IP ?= $(or $(call env_get,HOST_IP),10.0.2.15)
HOST_NAME ?= $(or $(call env_get,HOST_NAME),pve1)
HOST_DOMAIN ?= $(or $(call env_get,HOST_DOMAIN),daas-design.de)
NET_DEVICE ?= $(or $(call env_get,NET_DEVICE),enp0s4)
ISO_USER ?= root

CEPH_DISK ?= /dev/vdb
CEPH_NETWORK ?= 192.168.100.0/24
# reef (matches the Windows Ceph client in the ISOs) or squid
CEPH_VERSION ?= reef

CLUSTER_NAME ?= clustertest
CLUSTER_IP ?= 192.168.200.11

STANDALONE ?= $(call env_get,STANDALONE)
LINK_IP ?=

# Logging is controlled by DAAS_LOG_FILE (empty disables, default
# /var/log/daas-installer.log) and DAAS_DEBUG=1; make passes both through.

# Everything service.bash controls (see its header for what each one is)
SERVICES := auth daas frontend
CONTAINERS := guacd rabbit db extensions
IMAGES := x11vnc wine
HOST := nginx dnsmasq docker proxmox
COMPONENTS := $(SERVICES) $(CONTAINERS) $(IMAGES) $(HOST) iso
# Folder in installer/ with the Makefile of each image
IMAGE_DIR_db := mariadb
image_dir = $(or $(IMAGE_DIR_$(1)),$(1))
# Container name of each service container (as in src/config/container.toml)
CONTAINER_NAME_db := daas-0-mariadb
container_name = $(or $(CONTAINER_NAME_$(1)),daas-0-$(1))
ACTIONS := start stop restart status logs delete
LIFECYCLE := $(foreach c,$(COMPONENTS),$(addprefix $(c)-,$(ACTIONS)))
SERVICE_CMD = ./service.bash $(ENV_OPT)
# PURGE=1: *-delete / *-reinstall also delete the service's data
PURGE ?=
PURGE_OPT = $(if $(PURGE),-p)

# Installer steps depend on each other; never run them in parallel
.NOTPARALLEL:

# ============================================================
# Targets
# ============================================================

.PHONY: default usage help all install configure deps reset \
        $(ACTIONS) reinstall $(LIFECYCLE) \
        images images-delete containers-install images-install \
        proxmox-ensure iso-install iso-reinstall \
        $(foreach c,$(CONTAINERS) $(IMAGES),$(c)-install $(c)-reinstall) \
        proxmox-install proxmox-check \
        proxmox-install-ceph proxmox-install-ceph-osd \
        proxmox-install-ceph-cephfs proxmox-install-ceph-pool \
        proxmox-cluster-create proxmox-cluster-join \
        proxmox-isogen proxmox-isoupload require-pve \
        daas-all daas-install daas-configure daas-services daas-containers daas-check \
        daas-reinstall \
        frontend-all frontend-install frontend-configure frontend-reinstall frontend-check \
        env require-env auth-install auth-reinstall auth-check auth-backup auth-admin-password

default: usage

# ============================================================
# Help
# ============================================================

help: usage

usage:
	@echo ""
	@echo "Design DaaS - Installation (details: README.md in this folder)"
	@echo "=============================================================="
	@echo ""
	@echo "FIRST INSTALL (as root, on Debian 12)"
	@echo "  1. make env               Create $(notdir $(ENV_FILE)), then edit it (host, passwords)"
	@echo "  2. make install           Install everything. On a fresh Debian it stops after"
	@echo "                            the PVE kernel: reboot, then run it again."
	@echo "  3. make status            Check that everything runs"
	@echo ""
	@echo "  make install runs these steps, each one can also be run alone:"
	@echo "    proxmox-install         [1/7] Proxmox VE (two runs, reboot in between)"
	@echo "    deps                    [2/7] All host packages, docker-compose, root SSH key"
	@echo "    daas-install            [3/7] DaaS backend: Python venv, daas.service"
	@echo "    daas-configure                $(notdir $(ENV_FILE)) -> src/config/*.toml, nginx, TLS, dnsmasq"
	@echo "    images                  [4/7] Docker images: containers-install + images-install"
	@echo "    auth-install            [5/7] auth service (users, login) + its MariaDB"
	@echo "    frontend-all            [6/7] Frontend: nginx site :8443 + build + frontend.service"
	@echo "    daas-restart                  Start the DaaS backend (it starts the containers)"
	@echo "    iso-install             [7/7] Build the install ISOs, upload them (skip: SKIP_ISOS=1)"
	@echo ""
	@echo "EVERYDAY"
	@echo "  make start | stop | restart   auth, daas, frontend (daas starts the containers)"
	@echo "  make status               Everything, one line each"
	@echo "  make logs                 Follow auth, daas, frontend"
	@echo "  make configure            Re-apply $(notdir $(ENV_FILE)) (no rebuilds)"
	@echo "  make reinstall            After code changes: rebuild services and images"
	@echo "  make delete               Remove services, containers and images"
	@echo "  make reset CONFIRM=yes    Fresh start: delete ALL data + builds (then make install)"
	@echo ""
	@echo "  Options: PURGE=1          delete/reinstall also delete the data"
	@echo "                            (auth: DB + keys, daas: src/data + nginx site,"
	@echo "                            frontend: nginx site, db: src/data/db/mariadb)"
	@echo "           SKIP_ISOS=1      install without generating/uploading ISOs"
	@echo ""
	@echo "ONE COMPONENT  make <component>-<action>"
	@echo "  service    auth daas frontend           install start stop restart status logs delete reinstall"
	@echo "             proxmox-check, daas-check, frontend-check, auth-check: test the running parts"
	@echo "             auth-backup: save the auth service users/permissions + signing keys"
	@echo "  container  guacd rabbit db extensions   install start stop restart status logs delete reinstall"
	@echo "  image      x11vnc wine                  install status delete reinstall"
	@echo "  host       nginx dnsmasq docker proxmox start stop restart status logs"
	@echo "  iso                                     install status delete reinstall"
	@echo "  Groups:    make containers-install | images-install | images | images-delete"
	@echo "  e.g.       make db-restart   make db-logs   make extensions-reinstall"
	@echo ""
	@echo "PROXMOX (optional, multi-host setups)"
	@echo "  proxmox-install-ceph      Install Ceph (mon + mgr)"
	@echo "  proxmox-install-ceph-osd  Create OSD on CEPH_DISK"
	@echo "  proxmox-install-ceph-cephfs"
	@echo "  proxmox-install-ceph-pool"
	@echo "  proxmox-cluster-create    Needs LINK_IP"
	@echo "  proxmox-cluster-join      Needs LINK_IP"
	@echo "  proxmox-isogen            Generate ISOs ($(ISOTYPES))"
	@echo "  proxmox-isoupload         Copy ISOs into the daas-iso storage"
	@echo ""
	@echo "CONFIGURATION (command line > environment > $(notdir $(ENV_FILE)) > default)"
	@echo "  HOST_NUMBER=$(HOST_NUMBER)"
	@echo "  HOST_IP=$(HOST_IP)"
	@echo "  HOST_NAME=$(HOST_NAME)"
	@echo "  HOST_DOMAIN=$(HOST_DOMAIN)"
	@echo "  NET_DEVICE=$(NET_DEVICE)"
	@echo "  ISO_USER=$(ISO_USER)"
	@echo "  STANDALONE=$(STANDALONE)"
	@echo "  CEPH_DISK=$(CEPH_DISK)"
	@echo "  CEPH_NETWORK=$(CEPH_NETWORK)"
	@echo "  CEPH_VERSION=$(CEPH_VERSION)"
	@echo "  CLUSTER_NAME=$(CLUSTER_NAME)"
	@echo "  CLUSTER_IP=$(CLUSTER_IP)"
	@echo "  LINK_IP=$(LINK_IP)"
	@echo "  FRONTEND_FOLDER=$(FRONTEND_FOLDER)"
	@echo "  ENV_FILE=$(ENV_FILE) $(if $(wildcard $(ENV_FILE)),(found),(missing: make env))"
	@echo ""
	@echo "LOGGING"
	@echo "  DAAS_LOG_FILE=<path>      Log file (default /var/log/daas-installer.log)"
	@echo "  DAAS_DEBUG=1              Verbose output with shell tracing"
	@echo ""

# ============================================================
# Everything at once
# ============================================================

# stage N TITLE: banner between the steps of `make install`
stage = @printf '\n\033[1m==== [%s/7] %s ====\033[0m\n\n' "$(1)" "$(2)"

# Order matters:
#   - Proxmox first: its 1st run needs a reboot before anything else
#   - deps before every other step: they only check for their tools
#   - daas-configure writes nginx.conf + the certificate the frontend site uses
#   - the images before daas.service: the backend starts the containers
#   - auth before the DaaS backend: it checks logins against it
#   - the ISO upload needs the daas-iso storage, which the backend creates
#     on its first start
install: require-env
	$(call stage,1,Proxmox VE)
	$(MAKE) proxmox-ensure require-pve
	$(call stage,2,Host dependencies)
	$(MAKE) deps
	$(call stage,3,DaaS backend)
	$(MAKE) daas-install daas-configure
	$(call stage,4,Docker images)
	$(MAKE) images
	$(call stage,5,auth service)
	$(MAKE) auth-install
	$(call stage,6,Frontend + start)
	$(MAKE) frontend-all daas-restart
	$(call stage,7,ISOs)
	$(if $(SKIP_ISOS),@echo "Skipped (SKIP_ISOS=1)",$(MAKE) iso-install)
	@echo ""
	@echo "Everything installed. Check with: make status"
	@echo "Then open $(or $(call env_get,FRONTEND_PUBLIC_URL),https://$(HOST_NAME).$(HOST_DOMAIN):8443) (see README.md: Using it)"

all: install

deps:
	./deps/install.bash

# Fresh start: deletes ALL data of the DaaS stack and everything the
# installer built, then `make install` sets it up again. Kept: daas.env (all
# settings and passwords), src/config (incl. config/local), the ISOs and the
# Proxmox VMs. Asks for CONFIRM=yes because it cannot be undone.
reset:
	@[ "$(CONFIRM)" = yes ] || { \
		echo "make reset deletes ALL data of the DaaS stack, for good:"; \
		echo "  - the DaaS database (src/data/db/mariadb) and src/data"; \
		echo "  - the auth service's users, permissions and token keys"; \
		echo "  - all instance containers and user images (daas.*)"; \
		echo "  - the service containers and all images the installer built"; \
		echo "Kept: installer/daas.env, src/config, the ISOs, the Proxmox VMs."; \
		echo "Run: sudo make reset CONFIRM=yes"; exit 1; }
	$(SERVICE_CMD) delete -p all
	@ids="$$(docker ps -aq --filter name=^daas)"; \
	if [ -n "$$ids" ]; then echo "Removing instance containers: $$(docker ps -a --filter name=^daas --format '{{.Names}}' | tr '\n' ' ')"; docker rm -f $$ids >/dev/null; fi
	@imgs="$$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^daas[.-]' || true)"; \
	if [ -n "$$imgs" ]; then echo "Removing images: $$(echo $$imgs)"; docker image rm -f $$imgs >/dev/null; fi
	docker image prune -f
	@echo ""
	@echo "Reset done. Proxmox VMs are not touched:"
	@qm list 2>/dev/null | awk 'NR>1{print "  VM "$$1" "$$2" ("$$3")"}'
	@echo "Next: sudo make install SKIP_ISOS=1"

# Re-apply the env file without rebuilding (frontend URLs are baked into
# its build and auth settings into its container: use frontend-install /
# auth-install for those)
configure: require-env daas-configure frontend-configure daas-restart

# Service containers (started by the DaaS backend) + desktop images
images: containers-install images-install

containers-install: $(addsuffix -install,$(CONTAINERS))

images-install: $(addsuffix -install,$(IMAGES))

# Old names
daas-services: containers-install
daas-containers: images-install

images-delete:
	$(SERVICE_CMD) delete $(PURGE_OPT) containers images

# ============================================================
# Control
# ============================================================

# <svc>-<action>, e.g. auth-restart, frontend-delete (see service.bash)
$(LIFECYCLE):
	$(SERVICE_CMD) $(lastword $(subst -, ,$@)) $(if $(filter %-delete,$@),$(PURGE_OPT)) $(firstword $(subst -, ,$@))

# start, stop, ... on all services (stop/delete in reverse order)
$(ACTIONS):
	$(SERVICE_CMD) $@ $(if $(filter delete,$@),$(PURGE_OPT)) all

# Everything from the current code: services, service containers and
# desktop images (data is kept unless PURGE=1). The DaaS backend starts the
# containers again when it restarts.
reinstall: require-env
	$(MAKE) auth-reinstall
	$(MAKE) $(addsuffix -delete,$(CONTAINERS) $(IMAGES)) images
	$(MAKE) daas-reinstall frontend-reinstall

# ============================================================
# Images: service containers + desktop images
# ============================================================

# Build the image; a running container is restarted from the new image
# A running container is restarted only when the build changed its image
# (a restart of guacd or rabbit drops every open desktop session)
$(addsuffix -install,$(CONTAINERS)): %-install:
	$(MAKE) -C $(call image_dir,$*) build
	@running="$$(docker inspect -f '{{.Image}}' $(call container_name,$*) 2>/dev/null)"; \
	built="$$(docker image inspect -f '{{.Id}}' daas-0-$(call image_dir,$*))"; \
	if [ -z "$$running" ]; then echo "$* is not running"; \
	elif [ "$$running" = "$$built" ]; then echo "$* runs the current image, not restarted"; \
	else $(SERVICE_CMD) restart $*; fi

$(addsuffix -reinstall,$(CONTAINERS)): %-reinstall:
	$(MAKE) $*-delete $*-install $*-start

# Each image's Makefile builds it with both its tags (x11vnc + daas.contx11,
# wine + daas.contwine)
$(addsuffix -install,$(IMAGES)): %-install:
	$(MAKE) -C $* build

$(addsuffix -reinstall,$(IMAGES)): %-reinstall:
	$(MAKE) $*-delete $*-install

iso-install: proxmox-isogen proxmox-isoupload

iso-reinstall:
	$(MAKE) iso-delete iso-install

# ============================================================
# Proxmox
# ============================================================

# Fails with a hint while the host still runs the Debian kernel
# (proxmox-install needs a reboot between its two runs).
require-pve:
	@uname -r | grep -q pve || { \
		echo "Not running a PVE kernel yet: reboot, then run the same make command again."; \
		exit 1; }

# For `make install`: skip Proxmox when it is already set up, so a re-run
# does not upgrade the whole system
proxmox-ensure:
	@if uname -r | grep -q pve && command -v pveversion >/dev/null; then \
		echo "Proxmox already installed ($$(pveversion)), skipping proxmox-install"; \
	else \
		$(MAKE) proxmox-install; \
	fi

proxmox-install:
	./proxmox/install.bash -i "$(HOST_IP)" -h "$(HOST_NAME)" -d "$(HOST_DOMAIN)" -n "$(HOST_NUMBER)"

# Checks the Proxmox host layer (changes nothing)
proxmox-check:
	./proxmox/check.bash $(ENV_OPT)

proxmox-install-ceph:
	./proxmox/ceph.bash -a ceph -n "$(CEPH_NETWORK)" -v "$(CEPH_VERSION)"

proxmox-install-ceph-osd:
	./proxmox/ceph.bash -a osd -d "$(CEPH_DISK)"

proxmox-install-ceph-cephfs:
	./proxmox/ceph.bash -a cephfs

proxmox-install-ceph-pool:
	./proxmox/ceph.bash -a pool

proxmox-cluster-create:
	./proxmox/cluster.bash -c "$(CLUSTER_NAME)" -l "$(LINK_IP)"

proxmox-cluster-join:
	./proxmox/cluster.bash -i "$(CLUSTER_IP)" -l "$(LINK_IP)"

proxmox-isogen:
	$(MAKE) -C iso install
	$(foreach t,$(ISOTYPES),$(MAKE) -C iso ISOTYPE=$(t) USERNAME=$(ISO_USER) build check &&) true

proxmox-isoupload: require-pve
	./proxmox/isoupload.bash -s daas-iso $(foreach t,$(ISOTYPES),"$(ISODIR)/$(t)-daas.iso")

# ============================================================
# Design DaaS
# ============================================================

# Order matters: the backend starts the service containers itself, so the
# config and images must exist before daas.service is started.
daas-all: daas-install daas-configure images daas-restart

daas-install: require-pve
	./daas/install.bash -r "$(DESIGN_FOLDER)"

daas-configure:
	./daas/configure.bash \
		-r "$(DESIGN_FOLDER)" \
		-h "$(HOST_NAME)" \
		-d "$(HOST_DOMAIN)" \
		-i "$(HOST_NUMBER)" \
		-n "$(NET_DEVICE)" \
		-s "$(STANDALONE)" \
		$(ENV_OPT)

# Checks the running backend (changes nothing)
daas-check: require-env
	./daas/check.bash -e "$(ENV_FILE)"

# Fresh venv and unit from the current code; images are kept
# (rebuild them with make images)
daas-reinstall:
	$(MAKE) daas-delete daas-install daas-configure daas-restart

# ============================================================
# Frontend
# ============================================================

frontend-all: frontend-configure frontend-install

frontend-install:
	./frontend/install.bash -r "$(DESIGN_FOLDER)" -f "$(FRONTEND_FOLDER)" $(ENV_OPT)

frontend-configure:
	./frontend/configure.bash \
		-r "$(DESIGN_FOLDER)" \
		-f "$(FRONTEND_FOLDER)" \
		-h "$(HOST_NAME)" \
		$(ENV_OPT)

# Checks the running frontend like a browser (changes nothing)
frontend-check: require-env
	./frontend/check.bash -e "$(ENV_FILE)"

# PURGE=1 also removed the nginx site, so configure it again
frontend-reinstall:
	$(MAKE) frontend-delete $(if $(PURGE),frontend-configure) frontend-install

# ============================================================
# Env file + auth service
# ============================================================

env:
	@if [ -f "$(ENV_FILE)" ]; then \
		echo "$(ENV_FILE) already exists"; \
	else \
		install -m 600 daas.env.example "$(ENV_FILE)"; \
		echo "Created $(ENV_FILE): set HOST_*, ADMIN_* and AUTH_DB_* there"; \
	fi

require-env:
	@[ -f "$(ENV_FILE)" ] || { echo "Missing $(ENV_FILE): run 'make env' and edit it"; exit 1; }

auth-install: require-env
	./auth/install.bash -e "$(ENV_FILE)"

# Checks the running auth service (changes nothing)
auth-check: require-env
	./auth/check.bash -e "$(ENV_FILE)"

# Sets the auth service admin password to ADMIN_PASSWORD (after changing it in the
# env file) and revokes the admin's tokens
auth-admin-password: require-env
	./auth/set-admin-password.bash -e "$(ENV_FILE)"

# Saves the database (users, permissions) and signing keys to auth/backups/
auth-backup:
	./auth/backup.bash

auth-reinstall: require-env
	$(MAKE) auth-delete auth-install
