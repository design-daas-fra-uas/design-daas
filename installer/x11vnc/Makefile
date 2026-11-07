# Linux desktop image for DaaS container instances, see README.md.
# Run as root (docker, /root/.ssh/id_rsa.pub).

.PHONY: all prepare build run check shell stop clean

# x11vnc: the root image name (sent by the frontend as rootimage when a
# user builds a container environment); daas.contx11: the image the sample container
# object contx11 runs (src/app/daas/db/db_samples.py)
TAGS := x11vnc daas.contx11
IMAGE := $(firstword $(TAGS))
# Test container of `make run` / `make check`
NAME := x11vnc
VNC_PORT ?= 5901
SSH_PORT ?= 2221
# Must match vnc_password in src/app/daas/objects/config_factory.py
VNC_PASSWORD ?= user1234
# Public key the backend logs in with (created by `make deps`)
SSH_KEY ?= /root/.ssh/id_rsa.pub
AGENT_SRC := ../../src/app/daas/messaging
AGENT_ENV := ../../src/app/inst
BUILDOPT ?=

all: build

# Build context: the DaaS agent from src/ and the backend's ssh key
prepare:
	test -r $(SSH_KEY) || { echo "Missing $(SSH_KEY): run 'make deps' in installer/"; exit 1; }
	rm -rf agent
	mkdir -p agent/env
	cp -r $(AGENT_SRC)/* agent
	cp -r $(AGENT_ENV)/* agent/env
	cp $(SSH_KEY) authorized_keys

build: prepare
	docker build $(BUILDOPT) --build-arg VNC_PASSWORD=$(VNC_PASSWORD) \
		$(addprefix -t ,$(TAGS)) .

# Start a test container: VNC on 127.0.0.1:VNC_PORT, ssh on 127.0.0.1:SSH_PORT
run: stop
	docker run -d --rm --name $(NAME) \
		-p 127.0.0.1:$(VNC_PORT):5900 -p 127.0.0.1:$(SSH_PORT):22 $(IMAGE)

# Start a test container, check that everything in it runs, remove it
check:
	./check.bash $(IMAGE) $(NAME)

shell:
	docker exec -it $(NAME) bash

stop:
	-docker rm -f $(NAME) 2>/dev/null

clean: stop
	-docker image rm $(TAGS)
	rm -rf agent authorized_keys
