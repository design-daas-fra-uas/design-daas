#!/bin/bash

set -e

# VNC server
/usr/bin/Xtigervnc :0 \
    -rfbport 5900 \
    -localhost=0 \
    -SecurityTypes VncAuth,TLSVnc \
    -PasswordFile /tiger-vnc-password.txt \
    -geometry 1920x1080 \
    -desktop localhost:0 \
    -depth 24 \
    -auth /root/.Xauthority &

# SSH
service ssh start

# PulseAudio
pulseaudio --system --daemonize=yes \
    --disallow-exit \
    --exit-idle-time=-1
    
# Display configuration
export DISPLAY=:0

xrandr --output VNC-0 --mode 1280x800
xrdb -merge /root/.Xresources

# Qtile
qtile start &

# Wait for display initialization
sleep 2

# Start Wine application as wineuser
gosu wineuser env \
    DISPLAY=:0 \
    HOME=/home/wineuser \
    WINEARCH=win64 \
    WINEPREFIX=/home/wineuser/shared/.wine64 \
    wine /home/wineuser/shared/.wine64/drive_c/app.exe &

# lutris
chown wineuser:wineuser -R /home/wineuser
#sudo -u wineuser DISPLAY=:0 WINEARCH=win64 /usr/games/lutris &

# Keep container running
wait


