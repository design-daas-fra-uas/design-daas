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

# Services managed by service.bash, in start order
COMPONENTS := java daas frontend
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

.PHONY: default usage all install configure other \
        $(ACTIONS) reinstall $(LIFECYCLE) \
        proxmox-default proxmox-install proxmox-configure \
        proxmox-install-ceph proxmox-install-ceph-osd \
        proxmox-install-ceph-cephfs proxmox-install-ceph-pool \
        proxmox-cluster-create proxmox-cluster-join \
        proxmox-isogen proxmox-isoupload require-pve \
        daas-all daas-install daas-configure daas-services daas-containers \
        daas-reinstall \
        frontend-all frontend-install frontend-configure frontend-reinstall \
        env require-env java-install java-reinstall stack-all stack-configure

default: usage

# ============================================================
# Help
# ============================================================

usage:
	@echo ""
	@echo "Design DaaS - Installation"
	@echo "=========================="
	@echo ""
	@echo "FIRST INSTALL (in this order)"
	@echo "  make proxmox-install      # 1st run: PVE kernel, then reboot"
	@echo "  make proxmox-install      # 2nd run: Proxmox VE, docker, dnsmasq"
	@echo "  make daas-all             # backend: install, configure, images, start"
	@echo "  make frontend-all         # frontend (needs $(FRONTEND_FOLDER))"
	@echo ""
	@echo "STACK (DaaS + Java backend + frontend, settings in ENV_FILE)"
	@echo "  env                       Create $(notdir $(ENV_FILE)) from daas.env.example"
	@echo "  stack-all                 java-install, daas-configure, frontend-all, daas-restart"
	@echo "  stack-configure           Re-apply ENV_FILE to DaaS + nginx (no rebuilds)"
	@echo "  java-install              Java backend + its MariaDB (java-backend.service)"
	@echo ""
	@echo "COMMON"
	@echo "  all                       proxmox-install/configure + daas-all + other"
	@echo "  install                   proxmox-install + daas-install"
	@echo "  configure                 proxmox-configure + daas-configure"
	@echo "  other                     Generate and upload ISOs"
	@echo ""
	@echo "PROXMOX"
	@echo "  proxmox-default           install, configure, isogen, isoupload"
	@echo "  proxmox-install           Install Proxmox (two runs, see above)"
	@echo "  proxmox-configure         No-op (the backend creates bridges/storages)"
	@echo "  proxmox-install-ceph      Install Ceph (mon + mgr)"
	@echo "  proxmox-install-ceph-osd  Create OSD on CEPH_DISK"
	@echo "  proxmox-install-ceph-cephfs"
	@echo "  proxmox-install-ceph-pool"
	@echo "  proxmox-cluster-create    Needs LINK_IP"
	@echo "  proxmox-cluster-join      Needs LINK_IP"
	@echo "  proxmox-isogen            Generate ISOs ($(ISOTYPES))"
	@echo "  proxmox-isoupload         Copy ISOs into the daas-iso storage"
	@echo ""
	@echo "DAAS"
	@echo "  daas-all                  install, configure, services, containers, start"
	@echo "  daas-install              venv, nginx, docker-compose, systemd unit"
	@echo "  daas-configure            src/config/*.toml, nginx, src/data"
	@echo "  daas-services             Build guacd, rabbit, mariadb, extensions images"
	@echo "  daas-containers           Build x11vnc and wine desktop images"
	@echo "  daas-reinstall            delete, install, configure, restart"
	@echo ""
	@echo "FRONTEND"
	@echo "  frontend-all              configure + install"
	@echo "  frontend-install          Build the image from the current code, (re)start"
	@echo "  frontend-configure        nginx site :8443"
	@echo "  frontend-reinstall        delete + install"
	@echo ""
	@echo "JAVA BACKEND (auth + permissions, needs ENV_FILE)"
	@echo "  java-install              Build the image from the current code, (re)start"
	@echo "  java-reinstall            delete + install (database is kept)"
	@echo ""
	@echo "SERVICES  <svc> = java | daas | frontend"
	@echo "  <svc>-start / -stop / -restart / -status / -logs"
	@echo "  <svc>-delete              Remove the service (keeps its data)"
	@echo "  <svc>-reinstall           Delete, then install the current code"
	@echo "  PURGE=1                   With -delete/-reinstall: also delete the data"
	@echo "                            (java: DB + keys, daas: src/data + nginx site,"
	@echo "                            frontend: nginx site)"
	@echo "  start / stop / restart / status / logs / delete / reinstall"
	@echo "                            The same for all three services"
	@echo ""
	@echo "CONFIGURATION"
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
# Common
# ============================================================

# The ISO upload needs the daas-iso storage, which the backend creates on its
# first start, so the ISOs come after daas-all.
all: proxmox-install proxmox-configure daas-all other

install: proxmox-install daas-install

configure: proxmox-configure daas-configure

other: proxmox-isogen proxmox-isoupload

# ============================================================
# Control
# ============================================================

# <svc>-<action>, e.g. java-restart, frontend-delete (see service.bash)
$(LIFECYCLE):
	$(SERVICE_CMD) $(lastword $(subst -, ,$@)) $(if $(filter %-delete,$@),$(PURGE_OPT)) $(firstword $(subst -, ,$@))

# start, stop, ... on all services (stop/delete in reverse order)
$(ACTIONS):
	$(SERVICE_CMD) $@ $(if $(filter delete,$@),$(PURGE_OPT)) all

reinstall: java-reinstall daas-reinstall frontend-reinstall

# ============================================================
# Proxmox
# ============================================================

# proxmox-isoupload needs the backend to have run once (see `all`)
proxmox-default: proxmox-install proxmox-configure proxmox-isogen proxmox-isoupload

# Fails with a hint while the host still runs the Debian kernel
# (proxmox-install needs a reboot between its two runs).
require-pve:
	@uname -r | grep -q pve || { \
		echo "Not running a PVE kernel yet: reboot, then run 'make proxmox-install' again."; \
		exit 1; }

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

daas-services:
	$(MAKE) -C guacd build
	$(MAKE) -C rabbit build
	$(MAKE) -C mariadb build
	$(MAKE) -C extensions build

daas-containers:
	$(MAKE) -C x11vnc commit
	$(MAKE) -C wine commit

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
# Stack: DaaS + Java backend + frontend
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

# Java first: the DaaS backend checks logins against it
stack-all: require-env java-install daas-configure frontend-all daas-restart

# Apply changed settings without rebuilding (frontend URLs are baked into
# its build, so changing them needs frontend-install; Java settings need
# java-install)
stack-configure: require-env daas-configure frontend-configure daas-restart
