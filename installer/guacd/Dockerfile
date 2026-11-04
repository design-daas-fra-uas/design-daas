# guacd, the Guacamole proxy daemon (see README.md): translates between the
# Guacamole protocol (browser -> DaaS backend) and VNC/RDP/SSH of the
# instances. The DaaS backend starts it as daas-0-guacd on 127.0.0.1:4822
# (src/config/container.toml).

# bookworm: guacd 1.5.4 needs FreeRDP 2, trixie only has FreeRDP 3
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

# Build tools and the libraries of every guacd feature DaaS uses:
# VNC (libvncserver), RDP (freerdp2), SSH (libssh2), images (cairo, jpeg,
# png, webp), text (pango), sound (pulse, vorbis); ghostscript converts RDP
# print jobs to PDF
RUN apt-get update -y && apt-get upgrade -y \
    && apt-get install -y \
    build-essential \
    libcairo2-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
    libossp-uuid-dev libpango1.0-dev libssl-dev \
    libvncserver-dev freerdp2-dev libssh2-1-dev \
    libpulse-dev libvorbis-dev \
    ghostscript \
    && rm -rf /var/lib/apt/lists/*

# guacamole-server source, shipped in this folder (the Apache mirror URL
# is not stable); built and installed to /usr/local, source removed
ARG GUACD_VERSION=1.5.4
WORKDIR /usr/local/src
COPY guacamole-server-${GUACD_VERSION}.tar.gz .
RUN tar -xzf guacamole-server-${GUACD_VERSION}.tar.gz \
    && cd guacamole-server-${GUACD_VERSION} \
    && ./configure \
    && make \
    && make install \
    && ldconfig \
    && cd / && rm -rf /usr/local/src/guacamole-server-*
WORKDIR /

# debug logs every instruction; use info for less (docker run -e)
ENV GUACD_LOG_LEVEL=debug
EXPOSE 4822

# exec: guacd is PID 1, so the container stops (and the backend notices)
# when guacd dies
CMD ["sh", "-c", "exec guacd -b 0.0.0.0 -L \"$GUACD_LOG_LEVEL\" -f"]
