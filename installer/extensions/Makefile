# Extensions image (printing), see README.md. Run as root (docker,
# /root/.ssh/id_rsa.pub). The DaaS backend starts the container; here it is
# only built and tested.

.PHONY: all prepare build check clean

# Image name in src/config/container.toml
TAG := daas-0-extensions
# Public key the backend logs in with (created by `make deps`)
SSH_KEY ?= /root/.ssh/id_rsa.pub
BUILDOPT ?=

all: build

# Build context: the backend's ssh key (copied every time, so a new key
# reaches the image)
prepare:
	test -r $(SSH_KEY) || { echo "Missing $(SSH_KEY): run 'make deps' in installer/"; exit 1; }
	cp $(SSH_KEY) VNCService/id_rsa.pub

build: prepare
	docker build $(BUILDOPT) -t $(TAG) VNCService

# Start a test container (no published ports), print a test page, check
# that bad input is rejected, remove it
check:
	./check.bash $(TAG) $(TAG)-test

clean:
	-docker image rm $(TAG)
	rm -f VNCService/id_rsa.pub
