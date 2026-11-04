SHELL := /bin/bash

# ============================================================
# Configuration
# ============================================================

DESIGN_FOLDER := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

# Stack settings shared by DaaS, frontend and Java backend
# (copy daas.env.example to daas.env, or `make env`)
ENV_FILE ?= $(DESIGN_FOLDER)/installer/daas.env
# env_get KEY: value of KEY in ENV_FILE (empty if unset). Read with sed instead
# of `include` so values with $ or quotes are not mangled by make.
env_get = $(shell [ -f "$(ENV_FILE)" ] && sed -n 's/^$(1)=//p' "$(ENV_FILE)" | tail -n1 | sed -e 's/^"\(.*\)"$$/\1/' -e "s/^'\(.*\)'$$/\1/")
# -e <file> for the scripts when the env file exists
ENV_OPT = $(if $(wildcard $(ENV_FILE)),-e "$(ENV_FILE)")

FRONTEND_FOLDER ?= $(or $(call env_get,FRONTEND_FOLDER),$(abspath $(DESIGN_FOLDER)/../design-daas-application-frontend))

ISODIR := iso/iso
ISOTYPES := win10 win11 debian12

# Host configuration: command line > environment > ENV_FILE > default
HOST_NUMBER ?= $(or $(call env_get,HOST_NUMBER),11)
HOST_IP ?= $(or $(call env_get,HOST_IP),10.0.2.15)
HOST_NAME ?= $(or $(call env_get,HOST_NAME),pve1)
HOST_DOMAIN ?= $(or $(call env_get,HOST_DOMAIN),daas-design.de)
NET_DEVICE ?= $(or $(call env_get,NET_DEVICE),enp0s4)
ISO_USER ?= root

CEPH_DISK ?= /dev/vdb
CEPH_NETWORK ?= 192.168.100.0/24

CLUSTER_NAME ?= clustertest
CLUSTER_IP ?= 192.168.200.11

STANDALONE ?= $(call env_get,STANDALONE)
LINK_IP ?=

# Logging is controlled by DAAS_LOG_FILE (empty disables, default
# /var/log/daas-installer.log) and DAAS_DEBUG=1; make passes both through.

# Everything service.bash controls (see its header for what each one is)
SERVICES := java daas frontend
CONTAINERS := guacd rabbit db extensions
IMAGES := x11vnc wine
HOST := nginx dnsmasq docker proxmox
COMPONENTS := $(SERVICES) $(CONTAINERS) $(IMAGES) $(HOST) iso
# Folder in installer/ with the Makefile of each image
IMAGE_DIR_db := mariadb
image_dir = $(or $(IMAGE_DIR_$(1)),$(1))
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

.PHONY: default usage help all install configure other \
        $(ACTIONS) reinstall $(LIFECYCLE) \
        images images-delete proxmox-ensure iso-install iso-reinstall \
        $(foreach c,$(CONTAINERS) $(IMAGES),$(c)-install $(c)-reinstall) \
        proxmox-default proxmox-install proxmox-configure \
        proxmox-install-ceph proxmox-install-ceph-osd \
        proxmox-install-ceph-cephfs proxmox-install-ceph-pool \
        proxmox-cluster-create proxmox-cluster-join \
        proxmox-isogen proxmox-isoupload require-pve \
        daas-all daas-install daas-configure daas-services daas-containers \
        daas-reinstall \
        frontend-all frontend-install frontend-configure frontend-reinstall \
        env require-env java-install java-reinstall

default: usage

# ============================================================
# Help
# ============================================================

help: usage

usage:
	@echo ""
	@echo "Design DaaS - Installation"
	@echo "=========================="
	@echo ""
	@echo "EVERYDAY"
	@echo "  make env                  Once: create $(notdir $(ENV_FILE)), then edit it"
	@echo "  make install              Install EVERYTHING (Proxmox, images, Java, DaaS,"
	@echo "                            frontend, ISOs). On a fresh Debian it stops after"
	@echo "                            the PVE kernel: reboot and run it again."
	@echo "  make start | stop | restart   java, daas, frontend (daas starts the containers)"
	@echo "  make status               Everything, one line each"
	@echo "  make logs                 Follow java, daas, frontend"
	@echo "  make reinstall            After code changes: delete + install the services,"
	@echo "                            service containers and desktop images"
	@echo "  make configure            Re-apply $(notdir $(ENV_FILE)) (no rebuilds)"
	@echo "  make delete               Remove services, containers and images"
	@echo ""
	@echo "  Options: PURGE=1          delete/reinstall also delete the data"
	@echo "                            (java: DB + keys, daas: src/data + nginx site,"
	@echo "                            frontend: nginx site, db: src/data/db/mariadb)"
	@echo "           SKIP_ISOS=1      install without generating/uploading ISOs"
	@echo ""
	@echo "ONE COMPONENT  make <component>-<action>"
	@echo "  service    java daas frontend           install start stop restart status logs delete reinstall"
	@echo "  container  guacd rabbit db extensions   install start stop restart status logs delete reinstall"
	@echo "  image      x11vnc wine                  install status delete reinstall"
	@echo "  host       nginx dnsmasq docker proxmox start stop restart status logs"
	@echo "  iso                                     install status delete reinstall"
	@echo "  Groups:    make images | images-delete | daas-services | daas-containers"
	@echo "  e.g.       make db-restart   make db-logs   make extensions-reinstall"
	@echo ""
	@echo "DETAILS"
	@echo "  java-install              Build from the current code, (re)start"
	@echo "  daas-install              venv, nginx, docker-compose, systemd unit"
	@echo "  daas-configure            src/config/*.toml, nginx, src/data"
	@echo "  daas-services             Install guacd, rabbit, db, extensions"
	@echo "  daas-containers           Install x11vnc, wine"
	@echo "  frontend-install          Build from the current code, (re)start"
	@echo "  frontend-configure        nginx site :8443"
	@echo ""
	@echo "PROXMOX"
	@echo "  proxmox-install           Install Proxmox (two runs with a reboot between)"
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

# Order matters:
#   - nginx.conf (daas-configure) before the frontend site
#   - the images before daas.service: the backend starts the containers
#   - Java before the DaaS backend: it checks logins against it
#   - the ISO upload needs the daas-iso storage, which the backend creates
#     on its first start
install: require-env proxmox-ensure require-pve \
         daas-install daas-configure images \
         java-install frontend-all daas-restart \
         $(if $(SKIP_ISOS),,other)
	@echo ""
	@echo "Everything installed. Check with: make status"

all: install

# Re-apply the env file without rebuilding (frontend URLs are baked into
# its build and Java settings into its container: use frontend-install /
# java-install for those)
configure: require-env daas-configure frontend-configure daas-restart

other: iso-install

images: daas-services daas-containers

images-delete:
	$(SERVICE_CMD) delete $(PURGE_OPT) containers images

# ============================================================
# Control
# ============================================================

# <svc>-<action>, e.g. java-restart, frontend-delete (see service.bash)
$(LIFECYCLE):
	$(SERVICE_CMD) $(lastword $(subst -, ,$@)) $(if $(filter %-delete,$@),$(PURGE_OPT)) $(firstword $(subst -, ,$@))

# start, stop, ... on all services (stop/delete in reverse order)
$(ACTIONS):
	$(SERVICE_CMD) $@ $(if $(filter delete,$@),$(PURGE_OPT)) all

# Everything from the current code: services, service containers and
# desktop images (data is kept unless PURGE=1). The DaaS backend starts the
# containers again when it restarts.
reinstall: require-env
	$(MAKE) java-reinstall
	$(MAKE) $(addsuffix -delete,$(CONTAINERS) $(IMAGES)) images
	$(MAKE) daas-reinstall frontend-reinstall

# ============================================================
# Images: service containers + desktop images
# ============================================================

# Build the image; a running container is restarted from the new image
$(addsuffix -install,$(CONTAINERS)): %-install:
	$(MAKE) -C $(call image_dir,$*) build
	@if docker ps -q --filter "name=^daas-0-$*$$" | grep -q .; then \
		$(SERVICE_CMD) restart $*; fi

$(addsuffix -reinstall,$(CONTAINERS)): %-reinstall:
	$(MAKE) $*-delete $*-install $*-start

$(addsuffix -install,$(IMAGES)): %-install:
	$(MAKE) -C $* commit

$(addsuffix -reinstall,$(IMAGES)): %-reinstall:
	$(MAKE) $*-delete $*-install

iso-install: proxmox-isogen proxmox-isoupload

iso-reinstall:
	$(MAKE) iso-delete iso-install

# ============================================================
# Proxmox
# ============================================================

# proxmox-isoupload needs the backend to have run once (see `all`)
proxmox-default: proxmox-install proxmox-configure proxmox-isogen proxmox-isoupload

# Fails with a hint while the host still runs the Debian kernel
# (proxmox-install needs a reboot between its two runs).
require-pve:
	@uname -r | grep -q pve || { \
		echo "Not running a PVE kernel yet: reboot, then run the same make command again."; \
		exit 1; }

# For `make install`: skip Proxmox when it is already set up, so a re-run
# does not upgrade the whole system
proxmox-ensure:
	@if uname -r | grep -q pve && command -v pveversion >/dev/null \
		&& command -v docker >/dev/null && command -v dnsmasq >/dev/null; then \
		echo "Proxmox already installed ($$(pveversion)), skipping proxmox-install"; \
	else \
		$(MAKE) proxmox-install; \
	fi

proxmox-install:
	./proxmox/install.bash -i "$(HOST_IP)" -h "$(HOST_NAME)" -d "$(HOST_DOMAIN)" -n "$(HOST_NUMBER)"

proxmox-configure:
	./proxmox/configure.bash \
		-r "$(DESIGN_FOLDER)" \
		-h "$(HOST_NAME)" \
		-d "$(HOST_DOMAIN)" \
		-i "$(HOST_NUMBER)"

proxmox-install-ceph:
	./proxmox/ceph.bash -a ceph -n "$(CEPH_NETWORK)"

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
	$(foreach t,$(ISOTYPES),$(MAKE) -C iso ISOTYPE=$(t) USERNAME=$(ISO_USER) build &&) true

proxmox-isoupload: require-pve
	./proxmox/isoupload.bash -s daas-iso $(foreach t,$(ISOTYPES),"$(ISODIR)/$(t)-daas.iso")

# ============================================================
# Design DaaS
# ============================================================

# Order matters: the backend starts the service containers itself, so the
# config and images must exist before daas.service is started.
daas-all: daas-install daas-configure daas-services daas-containers daas-restart

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

daas-services: $(addsuffix -install,$(CONTAINERS))

daas-containers: $(addsuffix -install,$(IMAGES))

# Fresh venv and unit from the current code; images are kept
# (rebuild them with daas-services / daas-containers)
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

# PURGE=1 also removed the nginx site, so configure it again
frontend-reinstall:
	$(MAKE) frontend-delete $(if $(PURGE),frontend-configure) frontend-install

# ============================================================
# Env file + Java backend
# ============================================================

env:
	@if [ -f "$(ENV_FILE)" ]; then \
		echo "$(ENV_FILE) already exists"; \
	else \
		install -m 600 daas.env.example "$(ENV_FILE)"; \
		echo "Created $(ENV_FILE): set HOST_*, ADMIN_* and JAVA_DB_* there"; \
	fi

require-env:
	@[ -f "$(ENV_FILE)" ] || { echo "Missing $(ENV_FILE): run 'make env' and edit it"; exit 1; }

java-install: require-env
	./java/install.bash -e "$(ENV_FILE)"

java-reinstall: require-env
	$(MAKE) java-delete java-install
