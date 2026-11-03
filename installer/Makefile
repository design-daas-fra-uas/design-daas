SHELL:= /bin/bash

# ============================================================
# Configuration
# ============================================================

DESIGN_BASE := ..
DESIGN_FOLDER := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/$(DESIGN_BASE))
FRONTEND_FOLDER := $(DESIGN_FOLDER)/../design-daas-application-frontend

PY3CMD := cd "$(DESIGN_FOLDER)" && python3 -m backend.noweb.cmdline
ISODIR := installer/iso/iso

# User configuration
HOST_NUMBER ?= 11
HOST_IP ?= 10.0.2.15
HOST_NAME ?= pve1
HOST_DOMAIN ?= daas-design.de

CEPH_DISK ?= /dev/vdb
CEPH_NETWORK ?= 192.168.100.0/24

CLUSTER_NAME ?= clustertest
CLUSTER_IP ?= 192.168.200.11

STANDALONE ?=
LINK_IP ?=

# Services
SERVICES := frontend.service daas.service guacamole.service \
            pve-firewall.service pvedaemon.service \
            pve-ha-crm.service pve-ha-lrm.service \
            pve-lxc-syscalld.service pvefw-logger.service \
            pveproxy.service pvescheduler.service \
            pvestatd.service spiceproxy.service
            
# ============================================================
# Targets
# ============================================================

.PHONY: default all install configure other usage \
        start stop \
        proxmox-default proxmox-install proxmox-configure \
        proxmox-install-ceph proxmox-install-ceph-osd \
        proxmox-install-ceph-cephfs proxmox-install-ceph-pool \
        proxmox-cluster-create proxmox-cluster-join \
        proxmox-isogen proxmox-isoupload \
        guacamole-all guacamole-install guacamole-configure \
        daas-all daas-install daas-configure daas-containers daas-services \
        frontend-all frontend-install frontend-configure
        
default: usage

# ============================================================
# Help
# ============================================================

usage:
	@echo ""
	@echo "Design DaaS - Installation"
	@echo "========================="
	@echo ""
	@echo "COMMON"
	@echo "  all                    Install and configure everything"
	@echo "  install                Install all components"
	@echo "  configure              Configure all components"
	@echo "  other                  Generate and upload ISOs"
	@echo ""
	@echo "PROXMOX"
	@echo "  proxmox-default        Default Proxmox installation"
	@echo "  proxmox-install        Install Proxmox"
	@echo "  proxmox-configure      Configure Proxmox"
	@echo "  proxmox-install-ceph   Install Ceph"
	@echo "  proxmox-install-ceph-osd"
	@echo "  proxmox-install-ceph-cephfs"
	@echo "  proxmox-install-ceph-pool"
	@echo "  proxmox-cluster-create"
	@echo "  proxmox-cluster-join"
	@echo "  proxmox-isogen         Generate ISOs"
	@echo "  proxmox-isoupload      Upload ISOs"
	@echo ""
	@echo "GUACAMOLE"
	@echo "  guacamole-all"
	@echo "  guacamole-install"
	@echo "  guacamole-configure"
	@echo ""
	@echo "DAAS"
	@echo "  daas-all"
	@echo "  daas-install"
	@echo "  daas-configure"
	@echo "  daas-containers"
	@echo "  daas-services"
	@echo ""
	@echo "FRONTEND"
	@echo "  frontend-all"
	@echo "  frontend-install"
	@echo "  frontend-configure"
	@echo ""
	@echo "CONTROL"
	@echo "  start                  Start all services"
	@echo "  stop                   Stop all services"
	@echo ""
	@echo "CONFIGURATION"
	@echo "  HOST_NUMBER=$(HOST_NUMBER)"
	@echo "  HOST_IP=$(HOST_IP)"
	@echo "  HOST_NAME=$(HOST_NAME)"
	@echo "  HOST_DOMAIN=$(HOST_DOMAIN)"
	@echo "  CEPH_DISK=$(CEPH_DISK)"
	@echo "  CEPH_NETWORK=$(CEPH_NETWORK)"
	@echo "  CLUSTER_NAME=$(CLUSTER_NAME)"
	@echo "  CLUSTER_IP=$(CLUSTER_IP)"
	@echo "  LINK_IP=$(LINK_IP)"
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
	@echo "Starting services..."
	systemctl start $(SERVICES)

stop:
	@echo "Stopping services..."
	systemctl stop $(SERVICES)
	
# ============================================================
# Proxmox
# ============================================================

proxmox-default: proxmox-install proxmox-configure proxmox-isogen proxmox-isoupload

proxmox-install:
	@echo "Installing Proxmox..."
	./proxmox/install.bash -i "$(HOST_IP)" -h "$(HOST_NAME)" -d "$(HOST_DOMAIN)"

proxmox-configure:
	@echo "Configuring Proxmox..."
	./proxmox/configure.bash \
		-r "$(DESIGN_FOLDER)" \
		-h "$(HOST_NAME)" \
		-d "$(HOST_DOMAIN)" \
		-i "$(HOST_NUMBER)"

proxmox-install-ceph:
	@echo "Installing Ceph..."
	./proxmox/ceph.bash -a ceph -n "$(CEPH_NETWORK)"

proxmox-install-ceph-osd:
	@echo "Creating Ceph OSD..."
	./proxmox/ceph.bash -a osd -n "$(CEPH_NETWORK)" -d "$(CEPH_DISK)"

proxmox-install-ceph-cephfs:
	@echo "Installing CephFS..."
	./proxmox/ceph.bash -a cephfs -n "$(CEPH_NETWORK)"

proxmox-install-ceph-pool:
	@echo "Creating Ceph pool..."
	./proxmox/ceph.bash -a pool -n "$(CEPH_NETWORK)"

proxmox-cluster-create:
	@echo "Creating Proxmox cluster..."
	./proxmox/cluster.bash -c "$(CLUSTER_NAME)" -l "$(LINK_IP)"

proxmox-cluster-join:
	@echo "Joining Proxmox cluster..."
	./proxmox/cluster.bash -i "$(CLUSTER_IP)" -l "$(LINK_IP)"

proxmox-isogen:
	@echo "Generating installation ISOs..."
	$(MAKE) -C iso install
	$(MAKE) -C iso ISOTYPE=win10 build
	$(MAKE) -C iso ISOTYPE=win11 build
	$(MAKE) -C iso ISOTYPE=debian12 build
	
proxmox-isoupload:
	@echo "Uploading installation ISOs..."
	$(PY3CMD) prox-upload-iso "$(HOST_NAME)" "$(ISODIR)/debian12-daas.iso" daas-iso
	$(PY3CMD) prox-upload-iso "$(HOST_NAME)" "$(ISODIR)/win10-daas.iso" daas-iso
	$(PY3CMD) prox-upload-iso "$(HOST_NAME)" "$(ISODIR)/win11-daas.iso" daas-iso

# ============================================================
# Guacamole
# ============================================================

guacamole-all: guacamole-install guacamole-configure

guacamole/.env:
	@echo "Creating Guacamole environment file..."
	cp ./guacamole/.env-example ./guacamole/.env

guacamole-install: guacamole/.env
	@echo "Installing Guacamole..."
	cd guacamole && ./install.bash -r "$(DESIGN_FOLDER)"

guacamole-configure:
	@echo "Configuring Guacamole..."
	cd guacamole && ./configure.bash -r "$(DESIGN_FOLDER)"

# ============================================================
# Design DaaS
# ============================================================

daas-all: daas-install daas-configure daas-services daas-containers

daas-install:
	@echo "Installing Design DaaS..."
	cd daas && ./install.bash -r "$(DESIGN_FOLDER)"

daas-configure:
	@echo "Configuring Design DaaS..."
	cd daas && ./configure.bash \
		-r "$(DESIGN_FOLDER)" \
		-h "$(HOST_NAME)" \
		-d "$(HOST_DOMAIN)" \
		-i "$(HOST_NUMBER)" \
		-s "$(STANDALONE)"
		
daas-containers:
	@echo "Building DaaS containers..."
	$(MAKE) -C x11vnc commit
	$(MAKE) -C wine commit

daas-services:
	@echo "Building DaaS services..."
	$(MAKE) -C guacd build
	$(MAKE) -C rabbit build
	$(MAKE) -C mariadb build
	$(MAKE) -C extensions build

# ============================================================
# Frontend
# ============================================================

frontend-all: frontend-configure frontend-install

frontend-install:
	@echo "Installing frontend..."
	cd frontend && ./install.bash \
		-r "$(DESIGN_FOLDER)" \
		-f "$(FRONTEND_FOLDER)"

frontend-configure:
	@echo "Configuring frontend..."
	cd frontend && ./configure.bash \
		-r "$(DESIGN_FOLDER)" \
		-f "$(FRONTEND_FOLDER)" \
		-h "$(HOST_NAME)"
