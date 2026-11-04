# Wine desktop image: the x11vnc desktop plus Wine, for running Windows apps
# in DaaS container instances (see README.md).
#
# Everything else comes from the x11vnc image: entrypoint (sshd, VNC,
# pulseaudio, cups, DaaS agent, qtile), ssh key, VNC password, qtile config.
# Build x11vnc first, and rebuild this image after every x11vnc rebuild.
FROM x11vnc

ENV DEBIAN_FRONTEND=noninteractive

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

# The DaaS agent runs as root and starts the apps, so they use this prefix.
# Prepared at build time (fonts included), so the first app starts quickly.
ENV WINEARCH=win64
ENV WINEPREFIX=/root/.wine
RUN xvfb-run -a wineboot -u \
    && xvfb-run -a winetricks -q arial corefonts \
    && wineserver -w
# ssh sessions do not get the ENV above
RUN printf 'export WINEARCH=%s\nexport WINEPREFIX=%s\n' "$WINEARCH" "$WINEPREFIX" >> /root/.bashrc

# Desktop size of the wine instances (x11vnc default: 1920x1080)
ENV VNC_GEOMETRY=1280x800

# Test application (`make prepare` downloads it, see the Makefile)
COPY ./app.exe /root/.wine/drive_c/app.exe
