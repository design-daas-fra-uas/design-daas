# guacd image, see README.md. Run as root (docker).
# The DaaS backend starts the container; here it is only built and tested.

.PHONY: all build check clean

# Image name in src/config/container.toml
TAG := daas-0-guacd
# Must match the guacamole-server-<version>.tar.gz in this folder
GUACD_VERSION := 1.5.4
BUILDOPT ?=

all: build

build:
	test -f guacamole-server-$(GUACD_VERSION).tar.gz
	docker build $(BUILDOPT) --build-arg GUACD_VERSION=$(GUACD_VERSION) -t $(TAG) .

# Start a test container (no published ports), check guacd, remove it
check:
	./check.bash $(TAG) $(TAG)-test

clean:
	-docker image rm $(TAG)
