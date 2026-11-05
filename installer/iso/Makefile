# Unattended install ISOs for DaaS VMs, see README.md.
# Run as root (mounts ISOs, reads /root/.ssh/id_rsa.pub).

.PHONY: all help install build check clean clean-all \
        disk start stop ssh build-cluster disk-cluster start-cluster stop-cluster

SHELL := /bin/bash
# debian12 | win10 | win11 (devenv: see build-cluster)
ISOTYPE ?= debian12
# Account created in the VM, and its password
USERNAME ?= root
USERPASS ?= root
# Test VM (disk, start, ssh)
QCOWSIZE ?= 256
VMSSHPORT ?= 5555
EXTRAPORTS ?= 0
TIMEOUTS ?= 10000

INCFOLDER ?= cfg/$(ISOTYPE)
# win10 / win11 share one generator (-v 10|11), the others have their own
GENERATOR = $(if $(filter win%,$(ISOTYPE)),./scripts/generate-windows-iso.bash -v $(patsubst win%,%,$(ISOTYPE)),./scripts/generate-$(ISOTYPE)-iso.bash)
ISONAME := $(ISOTYPE)-daas
# Generated ISOs land in iso/<type>-daas.iso, next to the downloaded sources
ISOFILE := iso/$(ISONAME).iso

all: help

help:
	@echo "make [OPTION=VALUE] TARGET     (details: README.md)"
	@echo ""
	@echo "  install     Install the tools the generators need"
	@echo "  build       Build iso/<ISOTYPE>-daas.iso  (ISOTYPE=debian12|win10|win11)"
	@echo "  check       Check a built ISO: only the host's public key, no private key"
	@echo "  clean       Remove the build folders in out/ (keeps all ISOs)"
	@echo "  clean-all   Also remove the generated *-daas.iso files"
	@echo ""
	@echo "  Test VM on this host (qemu):  disk  start  stop  ssh"
	@echo "  Dev cluster (3 qemu nodes):   build-cluster  disk-cluster  start-cluster  stop-cluster"
	@echo ""
	@echo "  Options: ISOTYPE=$(ISOTYPE) USERNAME=$(USERNAME) USERPASS=... QCOWSIZE=$(QCOWSIZE)"
	@echo "           VMSSHPORT=$(VMSSHPORT) EXTRAPORTS=$(EXTRAPORTS) TIMEOUTS=$(TIMEOUTS)"
	@echo ""
	@echo "  Windows: downloads Microsoft's Enterprise Evaluation ISO itself (see README.md)."

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

install:
	./scripts/vm-run.bash -a install
	./scripts/generate-debian12-iso.bash -a install
	./scripts/generate-windows-iso.bash -v 10 -a install

build:
	$(GENERATOR) -a generate -i $(INCFOLDER) \
		-p $(USERPASS) -n $(ISONAME) -u $(USERNAME)
	@ls -la $(ISOFILE)

check:
	./check.bash $(ISOFILE)

clean: stop
	./scripts/generate-windows-iso.bash -v 10 -a clean
	./scripts/generate-windows-iso.bash -v 11 -a clean
	./scripts/generate-debian12-iso.bash -a clean

clean-all: clean
	rm -rf out
	rm -f iso/*-daas.iso

# ------------------------------------------------------------
# Test VM: boot the built ISO in qemu on this host
# ------------------------------------------------------------

disk:
	./scripts/vm-run.bash -a disk -n $(ISONAME) -s $(QCOWSIZE)

start:
	./scripts/vm-run.bash -a start -n $(ISONAME) -p $(VMSSHPORT) -e $(EXTRAPORTS)

stop:
	-./scripts/vm-run.bash -a stop -n $(ISONAME)

ssh:
	./scripts/vm-connect.bash -a connect -n $(ISONAME) \
		-p $(VMSSHPORT) -u $(USERNAME) -i $(INCFOLDER) -f pve -t $(TIMEOUTS)

# ------------------------------------------------------------
# Dev cluster: three Proxmox nodes in qemu (cfg/devenv)
# ------------------------------------------------------------

build-cluster:
	./scripts/generate-devenv-iso.bash -a generate -i cfg/devenv \
		-p $(USERPASS) -n devenv-daas -u $(USERNAME)

disk-cluster:
	./scripts/cluster-run.bash -a disk -n pve1 -s $(QCOWSIZE)
	./scripts/cluster-run.bash -a disk -n pve2 -s $(QCOWSIZE)
	./scripts/cluster-run.bash -a disk -n pve3 -s $(QCOWSIZE)

start-cluster:
	./scripts/cluster-run.bash -a netstart
	./scripts/cluster-run.bash -a start -n pve1
	./scripts/cluster-run.bash -a start -n pve2
	./scripts/cluster-run.bash -a start -n pve3

stop-cluster:
	./scripts/cluster-run.bash -a stop -n pve1
	./scripts/cluster-run.bash -a stop -n pve2
	./scripts/cluster-run.bash -a stop -n pve3
	./scripts/cluster-run.bash -a netstop
