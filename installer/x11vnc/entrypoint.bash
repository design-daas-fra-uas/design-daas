#!/bin/bash

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [x11vnc-entrypoint] $*"; }

log "Starting sshd"
service ssh start

export DISPLAY=:0

log "Starting Xtigervnc on $DISPLAY (rfb port 5900)"

/usr/bin/Xtigervnc "$DISPLAY" -rfbport 5900 -localhost=0 -SecurityTypes VncAuth,TLSVnc \
    -PasswordFile tiger-vnc-password.txt \
    -BlacklistTimeout 1000 -BlacklistThreshold 10000 -FrameRate 60 \
    -geometry 1920x1080 -desktop localhost:0 -depth 32 -auth /root/.Xauthority &

# Microphone input from the extensions container: raw PCM on :8080 -> virtual speaker
ncsocket() {
    while true; do
        nc -l -p 8080 | pacat --format=s16le --channels=1 --rate=44100 --device=virtual_speaker
        log "Microphone stream on :8080 closed, listening again"
    done
}

log "Starting pulseaudio"
pulseaudio &
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
