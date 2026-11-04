# Builds guacamole.js, the Guacamole JavaScript client that the DaaS viewer
# page loads (src/app/webroot/static/guacamole.js), see README.md.
# Not part of `make install`: the built file is committed. Run this only to
# rebuild or update it. Needs curl and internet access, not root.

.PHONY: all build install check clean

# apache/guacamole-client master right after the 1.5.3 release (2023-06-22):
# the committed guacamole.js is built from it, and the backend's protocol
# code links to it (src/app/daas/proxy/handshake.py, syntax.py)
GUAC_REF ?= 940c7ad37aefc06cb42c764a1deb6abab86f8290
# Guacamole.API_VERSION in the output (the source at GUAC_REF says 1.5.2)
GUAC_API_VERSION ?= 1.5.3

URL := https://github.com/apache/guacamole-client/archive/$(GUAC_REF).tar.gz
SRC := upstream/guacamole-client-$(GUAC_REF)/guacamole-common-js/src/main/webapp
TARGET := ../../src/app/webroot/static/guacamole.js

all: build

# Only the JavaScript part of the source archive, downloaded once per GUAC_REF
$(SRC):
	rm -rf upstream
	mkdir -p upstream
	curl -fsSL "$(URL)" | tar -xz -C upstream \
		guacamole-client-$(GUAC_REF)/guacamole-common-js/src/main/webapp

# Like the upstream build: the license header, then every module in name
# order, in one file. Written to a temp file first, so a failed build never
# leaves a broken guacamole.js behind.
build: $(SRC)
	LC_ALL=C cat $(SRC)/common/*.js $(SRC)/modules/*.js \
		| sed 's/^Guacamole.API_VERSION = ".*";$$/Guacamole.API_VERSION = "$(GUAC_API_VERSION)";/' \
		> guacamole.js.tmp
	mv guacamole.js.tmp guacamole.js
	@echo "Built guacamole.js ($$(wc -l < guacamole.js) lines, API $(GUAC_API_VERSION))"

# Copy the build to where the viewer page loads it from
install: build
	cp guacamole.js $(TARGET)
	@echo "Installed $(TARGET); restart the backend (make daas-restart) and reload the viewer"

# Is the committed file exactly what this Makefile builds?
check: build
	@if cmp -s guacamole.js $(TARGET); then \
		echo "OK: $(TARGET) is identical to the build of $(GUAC_REF)"; \
	else \
		echo "DIFFERENT: $(TARGET) is not the build of $(GUAC_REF):"; \
		diff guacamole.js $(TARGET) | head -20; exit 1; \
	fi

clean:
	rm -rf upstream guacamole.js guacamole.js.tmp
