FROM debian:bookworm

# Install essentials
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin

RUN apt-get update && apt-get install -y \
    x11vnc tigervnc-standalone-server xterm xvfb \
    openssh-server \
    python3 python3-pip python3-dev python3-distutils python3-setuptools \
    build-essential \
    net-tools netcat-traditional \
    ceph ceph-common ceph-fuse cups locales tzdata \
    galculator firefox-esr libreoffice \
    htop rofi gedit pulseaudio pulseeffects \
    systemd systemd-sysv systemd-timesyncd gnome-calculator \
    kitty vim \
    && rm -rf /var/lib/apt/lists/*
    
# Timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone
    
# Python dependencies
RUN python3 -m pip install --no-cache-dir --break-system-packages \
    dbus-next \
    pika \
    netifaces \
    click \
    psutil \
    xcffib \
    cairocffi \
    qtile

# Terminal
RUN echo 'export DISPLAY=:0' > /root/.bashrc \
    && echo 'export TERM=xterm' >> /root/.bashrc \
    && echo 'xterm*faceName: Monospace' > /root/.Xresources \
    && echo 'xterm*faceSize: 14' >> /root/.Xresources \
    && echo "de_DE.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen
    
# SSH
RUN mkdir -p /root/.ssh
COPY ./authorized_keys /root/.ssh/authorized_keys
RUN chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys
EXPOSE 22

# pulseaudio
ENV PA_OPTS="auth-ip-acl=172.17.0.0/24 auth-anonymous=1"

RUN echo "load-module module-null-sink" >> /etc/pulse/default.pa \
    && echo "load-module module-null-sink sink_name=\"virtual_speaker\" sink_properties=device.description=\"virtual_speaker\"" >> /etc/pulse/default.pa \
    && echo "load-module module-remap-source master=\"virtual_speaker.monitor\" source_name=\"virtual_mic\"" >> /etc/pulse/default.pa \
    && echo "load-module module-native-protocol-tcp $PA_OPTS" >> /etc/pulse/default.pa

# TigerVNC
COPY ./tiger-vnc-password.txt /tiger-vnc-password.txt
EXPOSE 5900

# Qtile
RUN mkdir -p /root/.config/qtile
COPY ./config.py /root/.config/qtile/config.py
COPY ./autostart.sh /root/.config/qtile/autostart.sh


# DAAS Environment
RUN mkdir -p /root/daas/qmsg \
    && mkdir -p /root/daas/env/adapter/tools
    
COPY ./qmsg/ /root/daas/

COPY ./daas.jpg /root/daas/env/daas.jpg
COPY ./daas-logo.png /root/daas/env/daas-logo.png

# COPY ./qmsg/env/*.py /root/daas/env/
# COPY ./qmsg/env/adapter/*.py /root/daas/env/adapter/
# COPY ./qmsg/env/adapter/tools/*.py /root/daas/env/adapter/tools/
# COPY ./qmsg/qmsg/*.py /root/daas/qmsg/
# COPY ./qmsg/qmsg/common/*.py /root/daas/qmsg/common/
# COPY ./qmsg/qmsg/sender/*.py /root/daas/qmsg/sender/
# COPY ./qmsg/qmsg/receiver/*.py /root/daas/qmsg/receiver/

# Python symlink
RUN ln -sf /usr/bin/python3 /usr/bin/python

# entrypoint
COPY ./entrypoint.bash /entrypoint.bash
RUN chmod a+x /entrypoint.bash

ENTRYPOINT ["/entrypoint.bash"]

