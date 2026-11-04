#!/bin/bash
#
# Entrypoint of the x11vnc desktop image. Starts, in this order:
#   sshd           :22    the backend runs commands in the instance over ssh
#   Xtigervnc :0   :5900  the desktop, VNC_GEOMETRY (default 1920x1080);
#                         guacd connects here (password file /tiger-vnc-password.txt)
#   pulseaudio     :4713  sound: virtual_speaker / virtual_mic, TCP for the
#                         extensions container
#   mic listener   :8080  raw PCM from the extensions container -> virtual_speaker
#   cupsd          :631   printing
#   DaaS agent            daas.runner_instance, talks to the backend over
#                         RabbitMQ on the docker host (172.17.0.1)
#   qtile                 window manager in the foreground: the container
#                         stops when it exits

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [x11vnc-entrypoint] $*"; }

# wait_for WHAT CMD...: retry CMD for up to 10s
wait_for() {
    local what="$1"
    shift
    for _ in $(seq 1 50); do
        "$@" >/dev/null 2>&1 && return 0
        sleep 0.2
    done
    log "WARN: $what not ready after 10s"
}

log "Starting sshd"
service ssh start

export DISPLAY=:0
VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"

log "Starting Xtigervnc on $DISPLAY (rfb port 5900, $VNC_GEOMETRY)"
/usr/bin/Xtigervnc "$DISPLAY" -rfbport 5900 -localhost=0 -SecurityTypes VncAuth,TLSVnc \
    -PasswordFile /tiger-vnc-password.txt \
    -BlacklistTimeout 1000 -BlacklistThreshold 10000 -FrameRate 60 \
    -geometry "$VNC_GEOMETRY" -desktop localhost:0 -depth 32 -auth /root/.Xauthority &
# xrdb/qtile fail if they start before the X server accepts connections
wait_for "X server" test -S /tmp/.X11-unix/X0

# Without --exit-idle-time=-1 pulseaudio quits after 20s without a client
log "Starting pulseaudio"
pulseaudio --daemonize=no --exit-idle-time=-1 &
wait_for "pulseaudio" pactl info

# Microphone input from the extensions container: raw PCM on :8080 -> virtual speaker
ncsocket() {
    while true; do
        nc -l -p 8080 | pacat --format=s16le --channels=1 --rate=44100 --device=virtual_speaker
        log "Microphone stream on :8080 closed, listening again"
    done
}
log "Starting microphone listener on :8080"
ncsocket &

log "Starting cupsd"
cupsd &

log "Starting DaaS agent (daas.runner_instance)"
cd /root || exit 1
python3 -m daas.runner_instance &

log "Starting qtile"
xrdb -merge ~/.Xresources
qtile start
