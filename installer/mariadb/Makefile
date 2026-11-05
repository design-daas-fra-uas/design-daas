# MariaDB image for the DaaS backend, see README.md. Run as root (docker).
# The DaaS backend starts the container; here it is only built and tested.

.PHONY: all build check clean

# Image name in src/config/container.toml
TAG := daas-0-mariadb
ENV_FILE ?= ../daas.env
# Root password: DAAS_DB_PASSWORD from the env file
ROOT_PASSWORD ?= $(shell sed -n 's/^DAAS_DB_PASSWORD=//p' "$(ENV_FILE)" 2>/dev/null | tail -n1)
BUILDOPT ?=

all: build

build:
	@[ -n "$(ROOT_PASSWORD)" ] || { echo "DAAS_DB_PASSWORD is not set in $(ENV_FILE)"; exit 1; }
	docker build $(BUILDOPT) --build-arg ROOT_PASSWORD="$(ROOT_PASSWORD)" -t $(TAG) .

# Starts a test container with its own empty data folder and port (does not
# touch daas-0-db), checks it, removes it
check:
	./check.bash $(TAG)

clean:
	-docker image rm $(TAG)
