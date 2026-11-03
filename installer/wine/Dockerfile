FROM x11vnc

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/wineuser
ENV WINEDEBUG=-all

# --------------------------------------------------
# Base system
# --------------------------------------------------
RUN apt-get update && apt-get upgrade -y

RUN apt-get install -y \
    x11vnc \
    tigervnc-standalone-server \
    openssh-server \
    xvfb \
    xterm \
    python3 \
    python3-pip \
    wget \
    curl \
    kitty \
    locales \
    vim \
    galculator \
    sudo \
    ca-certificates \
    apt-transport-https \
    cabextract \
    git \
    build-essential \
    gnupg \
    gosu \
    gpg-agent \
    p7zip \
    pulseaudio \
    pulseaudio-utils \
    unzip \
    winbind \
    meson \
    glslang-tools
	
# --------------------------------------------------
# Python packages
# --------------------------------------------------

RUN pip install --break-system-packages \
    click \
    psutil \
    xcffib \
    cairocffi \
    dbus-next \
    qtile

# --------------------------------------------------
# Wine architecture and WineHQ repository
# --------------------------------------------------

RUN dpkg --add-architecture i386

RUN mkdir -pm755 /etc/apt/keyrings

RUN wget -O /etc/apt/keyrings/winehq-archive.key \
    https://dl.winehq.org/wine-builds/winehq.key

RUN wget -NP /etc/apt/sources.list.d/ \
    https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources

RUN apt-get update

RUN apt-get install -y --install-recommends \
    wine32 \
    wine64 \
    curl \
    zenity \
    mono-complete

# Additional 32-bit libraries
RUN sed -i 's/main/main contrib non-free non-free-firmware/g' \
    /etc/apt/sources.list.d/debian.sources
    
RUN apt-get update && apt-get install -y \
    libasound2-plugins:i386 \
    libsdl2-2.0-0:i386 \
    libdbus-1-3:i386 \
    libsqlite3-0:i386 \
    gcc-multilib \
    g++-multilib

# --------------------------------------------------
# Winetricks
# --------------------------------------------------

RUN wget -O /usr/bin/winetricks \
    https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
    && chmod +x /usr/bin/winetricks

RUN wget -O /usr/share/bash-completion/completions/winetricks \
    https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks.bash-completion

RUN wget -O /usr/share/man/man1/winetricks.1 \
    https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks.1

# --------------------------------------------------
# Wine user
# --------------------------------------------------

RUN adduser --disabled-password --gecos "" wineuser \
    && usermod -aG sudo wineuser

# --------------------------------------------------
# Locale
# --------------------------------------------------

RUN echo "de_DE.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen

ENV LANG=de_DE.UTF-8
ENV LANGUAGE=de_DE:de
ENV LC_ALL=de_DE.UTF-8


# --------------------------------------------------
# SSH
# --------------------------------------------------

RUN mkdir -p /root/.ssh \
    && chmod 700 /root/.ssh

COPY ./authorized_keys /root/.ssh/authorized_keys

RUN chmod 600 /root/.ssh/authorized_keys

EXPOSE 22

# --------------------------------------------------
# DAAS directories and files
# --------------------------------------------------

RUN mkdir -p \
    /root/daas/env \
    /root/daas/qmsg \
    /root/daas/status \
    /root/.config/qtile

RUN touch /root/daas/status/cmdout.txt

COPY ./daas.jpg /root/daas/env/daas.jpg
COPY ./daas-logo.png /root/daas/env/daas-logo.png

RUN ln -sf /usr/bin/python3 /usr/bin/python

COPY ./config.py /root/.config/qtile/config.py

# --------------------------------------------------
# VNC
# --------------------------------------------------

COPY ./tiger-vnc-password.txt /tiger-vnc-password.txt

RUN chmod 600 /tiger-vnc-password.txt

EXPOSE 5900

# --------------------------------------------------
# Root configuration
# --------------------------------------------------

COPY ./.bashrc /root/.bashrc
COPY ./.Xresources /root/.Xresources

# --------------------------------------------------
# Thunderbird installer
# --------------------------------------------------

RUN mkdir -p /home/wineuser/shared/.wine64/drive_c

COPY ./app.exe /home/wineuser/shared/.wine64/drive_c/app.exe

RUN chmod +x /home/wineuser/shared/.wine64/drive_c/app.exe

# --------------------------------------------------
# Entrypoint
# --------------------------------------------------

COPY ./entrypoint.bash /entrypoint.bash

RUN chmod +x /entrypoint.bash

# --------------------------------------------------
# Wine prefix initialization
# --------------------------------------------------

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends strace && \
    rm -rf /var/lib/apt/lists/*

RUN chmod 1777 /tmp && \
    mkdir -p /home/wineuser/shared && \
    chown -R wineuser:wineuser /home/wineuser

USER wineuser

WORKDIR /home/wineuser

ENV HOME=/home/wineuser
ENV WINEARCH=win64
ENV WINEPREFIX=/home/wineuser/shared/.wine64
ENV WINEDEBUG=-all
ENV XDG_RUNTIME_DIR=/tmp

# --------------------------------------------------
# Test Wine server socket creation
# --------------------------------------------------

RUN --security=insecure \
    echo "===== USER =====" && \
    id && \
    echo "===== ENVIRONMENT =====" && \
    env | grep -E 'HOME|WINE|XDG' && \
    echo "===== TEMP DIRECTORY =====" && \
    ls -ld /tmp && \
    echo "===== WINE SERVER TEST =====" && \
    strace -f -o /tmp/wineserver.strace wineserver -p

# --------------------------------------------------
# Clean stale Wine sockets
# --------------------------------------------------

RUN --security=insecure \
    wineserver -k || true

RUN rm -rf /tmp/.wine-*

# --------------------------------------------------
# Initialize 64-bit Wine prefix
# --------------------------------------------------

RUN --security=insecure \
    WINEARCH=win64 \
    WINEPREFIX=/home/wineuser/shared/.wine64 \
    wineboot --init

# Wait for wineserver to finish
RUN --security=insecure wineserver -w

# --------------------------------------------------
# Install fonts
# --------------------------------------------------

RUN --security=insecure \
    xvfb-run -a winetricks -q arial corefonts

RUN --security=insecure wineserver -w

# --------------------------------------------------
# Finish
# --------------------------------------------------

USER root

WORKDIR /

ENTRYPOINT ["/entrypoint.bash"]
