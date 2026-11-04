# Wine desktop image for DaaS container instances: a Linux desktop plus
# Wine, for running Windows apps (see README.md).
# Build it with `make build`: the build context needs the DaaS agent (agent/),
# authorized_keys and app.exe, which `make prepare` puts there.

# trixie: the image needs python3 >= 3.11 for qtile and the agent
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin

# Desktop (X server, window manager, apps), sound, printing, ssh, ceph
# (shared folders) and the Python modules of the DaaS agent
RUN apt-get update -y && apt-get upgrade -y \
    && apt-get install -y \
    x11vnc tigervnc-standalone-server xterm xvfb \
    openssh-server python3 pip kitty vim net-tools netcat-traditional \
    ceph ceph-common ceph-fuse cups locales tzdata \
    galculator firefox-esr libreoffice \
    htop rofi gedit pulseaudio pulseeffects \
    systemd systemd-sysv systemd-timesyncd gnome-calculator \
    && rm -rf /var/lib/apt/lists/*
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN pip install --no-cache-dir --break-system-packages \
    setuptools wheel && \
    pip install --no-cache-dir --break-system-packages \
    dbus-next pika netifaces click psutil xcffib cairocffi qtile

# Wine (64 + 32 bit) from Debian, winetricks from contrib, and what Windows
# apps commonly need: 32-bit sound/SDL libraries, cabextract/7z/unzip for
# winetricks, zenity for its dialogs, winbind for NTLM logins, mono
RUN dpkg --add-architecture i386 \
    && sed -i 's/^Components: main$/Components: main contrib/' /etc/apt/sources.list.d/debian.sources \
    && apt-get update -y \
    && apt-get install -y --install-recommends \
    wine wine32 wine64 winetricks \
    libasound2-plugins:i386 libsdl2-2.0-0:i386 libdbus-1-3:i386 libsqlite3-0:i386 \
    cabextract p7zip unzip zenity winbind mono-complete \
    && rm -rf /var/lib/apt/lists/*

# Terminal
RUN echo 'export DISPLAY=:0' > /root/.bashrc \
    && echo 'export TERM=xterm' >> /root/.bashrc \
    && echo 'xterm*faceName: Monospace' > /root/.Xresources \
    && echo 'xterm*faceSize: 14' >> /root/.Xresources \
    && echo "de_DE.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen

# The DaaS agent runs as root and starts the apps, so they use this prefix.
# Prepared at build time (fonts included), so the first app starts quickly.
ENV WINEARCH=win64
ENV WINEPREFIX=/root/.wine
RUN xvfb-run -a wineboot -u \
    && xvfb-run -a winetricks -q arial corefonts \
    && wineserver -w
# ssh sessions do not get the ENV above
RUN printf 'export WINEARCH=%s\nexport WINEPREFIX=%s\n' "$WINEARCH" "$WINEPREFIX" >> /root/.bashrc

# ssh: the backend logs in as root with the host's /root/.ssh/id_rsa
COPY ./authorized_keys /root/.ssh/authorized_keys
EXPOSE 22

# pulseaudio: a virtual speaker (its monitor is the virtual mic) and TCP
# access for the containers on the docker bridge (extensions container)
ENV PA_OPTS="auth-ip-acl=172.17.0.0/24 auth-anonymous=1"
RUN printf '%s\n' \
    'load-module module-null-sink' \
    'load-module module-null-sink sink_name="virtual_speaker" sink_properties=device.description="virtual_speaker"' \
    'load-module module-remap-source master="virtual_speaker.monitor" source_name="virtual_mic"' \
    "load-module module-native-protocol-tcp $PA_OPTS" \
    >> /etc/pulse/default.pa

# tigervnc: guacd logs in with this password (vnc_password in
# src/app/daas/objects/config_factory.py), so change both together
ARG VNC_PASSWORD=user1234
RUN echo "$VNC_PASSWORD" | vncpasswd -f > /tiger-vnc-password.txt \
    && chmod 600 /tiger-vnc-password.txt
EXPOSE 5900

# qtile
COPY ./config.py /root/.config/qtile/config.py

# DaaS agent (src/app/daas/messaging + src/app/inst), run as daas.runner_instance
COPY ./agent/ /root/daas/
COPY ./daas.jpg ./daas-logo.png /root/daas/env/
RUN ln -s /usr/bin/python3 /usr/bin/python

# Test application (`make prepare` downloads it, see the Makefile)
COPY ./app.exe /root/.wine/drive_c/app.exe

# entrypoint
COPY ./entrypoint.bash /entrypoint.bash
RUN chmod a+x /entrypoint.bash
ENTRYPOINT [ "/entrypoint.bash" ]
