# Extensions container: printing for the instances (see ../README.md).
# The DaaS backend starts it as daas-0-extensions (src/config/container.toml)
# and reaches it over ssh (create printers) and the websocket on :8010.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Node.js 24 LTS (nodesource), CUPS with the cups-pdf printer driver, ssh for
# the backend, curl for scripts/postprocess.sh
RUN apt-get update && \
    apt-get install -y curl openssh-server && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs cups cups-pdf && \
    rm -rf /var/lib/apt/lists/*

# ssh: the backend logs in as root with the host's /root/.ssh/id_rsa
COPY id_rsa.pub /root/.ssh/authorized_keys

WORKDIR /usr/src/app

# Printer server (server.js), dependencies from package-lock.json
COPY package*.json ./
RUN npm ci
COPY server.js ./
COPY scripts/ ./scripts/
RUN chmod 755 scripts/*.sh

# CUPS listens on all addresses so the instances can print over IPP
COPY scripts/cupsd.conf /etc/cups/cupsd.conf

EXPOSE 22 631 8010

CMD service dbus start && service ssh start && service cups start && exec node server.js
