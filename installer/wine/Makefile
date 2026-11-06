# Wine desktop image for DaaS container instances, see README.md.
# Run as root (docker, /root/.ssh/id_rsa.pub).

.PHONY: all prepare build run check shell stop clean

# wine: the root image name (sent by the frontend as rootimage, and
# DEFAULT_CNT_IMAGE of new containers in src/app/plugins/platform/phases/phases_tasks.py); daas.contwine: the image the sample
# container object contwine runs (src/app/daas/db/db_samples.py)
TAGS := wine daas.contwine
IMAGE := $(firstword $(TAGS))
# Test container of `make run` / `make check`
NAME := wine
VNC_PORT ?= 5902
SSH_PORT ?= 2222
# Must match vnc_password in src/app/daas/objects/config_factory.py
VNC_PASSWORD ?= user1234
# Public key the backend logs in with (created by `make deps`)
SSH_KEY ?= /root/.ssh/id_rsa.pub
AGENT_SRC := ../../src/app/daas/messaging
AGENT_ENV := ../../src/app/inst
# Test application put into the prefix as C:\app.exe
APP_URL := https://download-installer.cdn.mozilla.net/pub/thunderbird/releases/115.6.1/win64/de/Thunderbird%20Setup%20115.6.1.exe
BUILDOPT ?=

all: build

# Build context: the DaaS agent from src/, the backend's ssh key, the test app
prepare:
	test -r $(SSH_KEY) || { echo "Missing $(SSH_KEY): run 'make deps' in installer/"; exit 1; }
	rm -rf agent
	mkdir -p agent/env
	cp -r $(AGENT_SRC)/* agent
	cp -r $(AGENT_ENV)/* agent/env
	cp $(SSH_KEY) authorized_keys
	test -f app.exe || curl -fL -o app.exe "$(APP_URL)"

build: prepare
	docker build $(BUILDOPT) --build-arg VNC_PASSWORD=$(VNC_PASSWORD) \
		$(addprefix -t ,$(TAGS)) .

# Start a test container: VNC on 127.0.0.1:VNC_PORT, ssh on 127.0.0.1:SSH_PORT
run: stop
	docker run -d --rm --name $(NAME) \
		-p 127.0.0.1:$(VNC_PORT):5900 -p 127.0.0.1:$(SSH_PORT):22 $(IMAGE)

# Start a test container, check the desktop and Wine in it, remove it
check:
	./check.bash $(IMAGE) $(NAME)

shell:
	docker exec -it $(NAME) bash

stop:
	-docker rm -f $(NAME) 2>/dev/null

clean: stop
	-docker image rm $(TAGS)
	rm -rf agent authorized_keys app.exe
