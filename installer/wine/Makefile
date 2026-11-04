# Wine desktop image for DaaS container instances, see README.md.
# Run as root. Builds on the x11vnc image: build that first.

.PHONY: all prepare build run check shell stop clean

# wine: the root image name (default_wine_image_name in src/config/files.toml,
# DEFAULT_CNT_IMAGE of new containers); daas.contwine: the image the sample
# container object contwine runs (src/app/daas/db/db_samples.py)
TAGS := wine daas.contwine
IMAGE := $(firstword $(TAGS))
BASE := x11vnc
# Test container of `make run` / `make check`
NAME := wine
VNC_PORT ?= 5902
SSH_PORT ?= 2222
# Test application put into the prefix as C:\app.exe
APP_URL := https://download-installer.cdn.mozilla.net/pub/thunderbird/releases/115.6.1/win64/de/Thunderbird%20Setup%20115.6.1.exe
BUILDOPT ?=

all: build

prepare:
	docker image inspect $(BASE) >/dev/null 2>&1 || { echo "Missing image $(BASE): run 'make x11vnc-install' in installer/ first"; exit 1; }
	test -f app.exe || curl -fL -o app.exe "$(APP_URL)"

build: prepare
	docker build $(BUILDOPT) $(addprefix -t ,$(TAGS)) .

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
	rm -f app.exe
