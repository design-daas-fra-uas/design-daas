FROM node:22-bookworm

ENV DEBIAN_FRONTEND=noninteractive

# Install system requirements
RUN apt-get update && \
    apt-get install -y \
    curl \
    ssh \
    openssh-server \
    ca-certificates \
    gnupg \
    dbus \
    cups \
    dos2unix && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Verify Node.js and npm
RUN node --version && npm --version

# Set default root password
RUN echo "root:root" | chpasswd

# Configure SSH
COPY id_rsa.pub /root/.ssh/authorized_keys

# Set working directory
WORKDIR /usr/src/app

# Install Express dependencies
COPY package*.json ./
RUN npm install

# Copy application
COPY . .

# Fix line endings
RUN dos2unix ./scripts/create_printer.sh \
    ./scripts/delete_printer.sh \
    ./scripts/postprocess.sh

# Configure CUPS
COPY scripts/cupsd.conf /etc/cups/cupsd.conf

RUN chmod -R 777 ./scripts/*.sh

EXPOSE 8010
EXPOSE 631
EXPOSE 22

CMD service dbus start && \
    service ssh start && \
    service cups start && \
    node server.js
