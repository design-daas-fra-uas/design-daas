FROM debian:bookworm

# Install essentials
ENV DEBIAN_FRONTEND=noninteractive

# Build dependencies
RUN apt update -y && apt upgrade -y && \
    apt install -y \
    build-essential \
    cmake \
    libcairo2-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libossp-uuid-dev \
    freerdp2-dev \
    libfreerdp2-2 \
    libpango1.0-dev \
    libssh2-1-dev \
    libssl-dev \
    libvncserver-dev \
    libpulse-dev \
    libvorbis-dev \
    libwebp-dev \
    wget

# guacamole-server source (shipped in this folder, the Apache mirror URL is not stable)
WORKDIR /usr/local/src
COPY guacamole-server-1.5.4.tar.gz .
RUN tar -xzf guacamole-server-1.5.4.tar.gz && rm guacamole-server-1.5.4.tar.gz

# Build guacd
WORKDIR /usr/local/src/guacamole-server-1.5.4
RUN ./configure --with-init-dir=/etc/init.d && \
    make && \
    make install && \
    ldconfig
# guacamole.properties is written by entrypoint.bash
RUN mkdir -p /etc/guacamole
RUN apt-get install -y ghostscript cups-bsd

# Expose guacd default port
ENV GUACD_LOG_LEVEL=debug
EXPOSE 4822

# Run guacd
CMD ["guacd", "-f"]

# entrypoint
COPY ./entrypoint.bash /entrypoint.bash
RUN chmod a+x /entrypoint.bash
ENTRYPOINT [ "/entrypoint.bash" ]

