.PHONY: all build clean

TAG := daas-0-mariadb
BUILDOPT?=
DOCKER := sudo docker

# Build image only. Runtime is managed by DAAS.
all: build

build:
	$(DOCKER) build $(BUILDOPT) -t $(TAG) .

clean: stop
	-$(DOCKER) rmi $(TAG)
