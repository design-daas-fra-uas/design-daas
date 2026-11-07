# RabbitMQ broker image, see README.md. Run as root (docker).
# The DaaS backend starts the container; here it is only built and tested.

.PHONY: all build check clean

# Image name in src/config/container.toml
TAG := daas-0-rabbit
BUILDOPT ?=

all: build

build:
	docker build $(BUILDOPT) -t $(TAG) .

# Start a test container (no published ports), check the broker, remove it
check:
	./check.bash $(TAG) $(TAG)-test

clean:
	-docker image rm $(TAG)
