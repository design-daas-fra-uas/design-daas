SHELL := /bin/bash

# ============================================================
# Configuration
# ============================================================

DESIGN_FOLDER := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
FRONTEND_FOLDER ?= $(abspath $(DESIGN_FOLDER)/../design-daas-application-frontend)

ISODIR := iso/iso
ISOTYPES := win10 win11 debian12

# User configuration (override on the command line: make HOST_NAME=pve2 ...)
HOST_NUMBER ?= 11
HOST_IP ?= 10.0.2.15
HOST_NAME ?= pve1
HOST_DOMAIN ?= daas-design.de
NET_DEVICE ?= enp0s4

CEPH_DISK ?= /dev/vdb
CEPH_NETWORK ?= 192.168.100.0/24

CLUSTER_NAME ?= clustertest
CLUSTER_IP ?= 192.168.200.11

STANDALONE ?=
LINK_IP ?=

# Logging is controlled by DAAS_LOG_FILE (empty disables, default
# /var/log/daas-installer.log) and DAAS_DEBUG=1; make passes both through.

# Services
SERVICES := frontend.service daas.service \
            pve-firewall.service pvedaemon.service \
            pve-ha-crm.service pve-ha-lrm.service \
            pve-lxc-syscalld.service pvefw-logger.service \
            pveproxy.service pvescheduler.service \
            pvestatd.service spiceproxy.service

# ============================================================
# Targets
# ============================================================

.PHONY: default usage all install configure other \
        start stop status logs \
        proxmox-default proxmox-install proxmox-configure \
        proxmox-install-ceph proxmox-install-ceph-osd \
        proxmox-install-ceph-cephfs proxmox-install-ceph-pool \
        proxmox-cluster-create proxmox-cluster-join \
        proxmox-isogen proxmox-isoupload \
        daas-all daas-install daas-configure daas-services daas-containers \
        daas-start daas-stop \
        frontend-all frontend-install frontend-configure

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
	@echo "COMMON"
	@echo "  all                       proxmox-default + daas-all"
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
	@echo "  daas-start / daas-stop    (Re)start / stop daas.service"
	@echo ""
	@echo "FRONTEND"
	@echo "  frontend-all              configure + install"
	@echo "  frontend-install"
	@echo "  frontend-configure"
	@echo ""
	@echo "CONTROL"
	@echo "  start / stop              Start / stop all services"
	@echo "  status                    Show service status"
	@echo "  logs                      Follow the backend + frontend logs"
	@echo ""
	@echo "CONFIGURATION"
	@echo "  HOST_NUMBER=$(HOST_NUMBER)"
	@echo "  HOST_IP=$(HOST_IP)"
	@echo "  HOST_NAME=$(HOST_NAME)"
	@echo "  HOST_DOMAIN=$(HOST_DOMAIN)"
	@echo "  NET_DEVICE=$(NET_DEVICE)"
	@echo "  STANDALONE=$(STANDALONE)"
	@echo "  CEPH_DISK=$(CEPH_DISK)"
	@echo "  CEPH_NETWORK=$(CEPH_NETWORK)"
	@echo "  CLUSTER_NAME=$(CLUSTER_NAME)"
	@echo "  CLUSTER_IP=$(CLUSTER_IP)"
	@echo "  LINK_IP=$(LINK_IP)"
	@echo "  FRONTEND_FOLDER=$(FRONTEND_FOLDER)"
	@echo ""
	@echo "LOGGING"
	@echo "  DAAS_LOG_FILE=<path>      Log file (default /var/log/daas-installer.log)"
	@echo "  DAAS_DEBUG=1              Verbose output with shell tracing"
	@echo ""

# ============================================================
# Common
# ============================================================

all: proxmox-default daas-all

install: proxmox-install daas-install

configure: proxmox-configure daas-configure

other: proxmox-isogen proxmox-isoupload

# ============================================================
# Control
# ============================================================

start:
	systemctl start $(SERVICES)

stop:
	systemctl stop $(SERVICES)

status:
	-systemctl --no-pager status $(SERVICES)

logs:
	journalctl -f -u daas.service -u frontend.service

# ============================================================
# Proxmox
# ============================================================

proxmox-default: proxmox-install proxmox-configure proxmox-isogen proxmox-isoupload

proxmox-install:
	./proxmox/install.bash -i "$(HOST_IP)" -h "$(HOST_NAME)" -d "$(HOST_DOMAIN)"

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
	$(foreach t,$(ISOTYPES),$(MAKE) -C iso ISOTYPE=$(t) build &&) true

proxmox-isoupload:
	./proxmox/isoupload.bash -s daas-iso $(foreach t,$(ISOTYPES),"$(ISODIR)/$(t)-daas.iso")

# ============================================================
# Design DaaS
# ============================================================

# Order matters: the backend starts the service containers itself, so the
# config and images must exist before daas.service is started.
daas-all: daas-install daas-configure daas-services daas-containers daas-start

daas-install:
	./daas/install.bash -r "$(DESIGN_FOLDER)"

daas-configure:
	./daas/configure.bash \
		-r "$(DESIGN_FOLDER)" \
		-h "$(HOST_NAME)" \
		-d "$(HOST_DOMAIN)" \
		-i "$(HOST_NUMBER)" \
		-n "$(NET_DEVICE)" \
		-s "$(STANDALONE)"

daas-services:
	$(MAKE) -C guacd build
	$(MAKE) -C rabbit build
	$(MAKE) -C mariadb build
	$(MAKE) -C extensions build

daas-containers:
	$(MAKE) -C x11vnc commit
	$(MAKE) -C wine commit

daas-start:
	systemctl restart daas.service
	@sleep 2
	@systemctl is-active --quiet daas.service \
		&& echo "daas.service running (logs: journalctl -u daas -f)" \
		|| { journalctl -u daas.service -n 50 --no-pager; exit 1; }

daas-stop:
	systemctl stop daas.service

# ============================================================
# Frontend
# ============================================================

frontend-all: frontend-configure frontend-install

frontend-install:
	./frontend/install.bash -r "$(DESIGN_FOLDER)" -f "$(FRONTEND_FOLDER)"

frontend-configure:
	./frontend/configure.bash \
		-r "$(DESIGN_FOLDER)" \
		-f "$(FRONTEND_FOLDER)" \
		-h "$(HOST_NAME)"
