#!/bin/bash

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [guacd-entrypoint] $*"; }

log "Starting pulseaudio"
pulseaudio &

echo "remote-cursor: local" > /etc/guacamole/guacamole.properties

# guacd runs in the foreground as PID 1, so the container stops (and the
# backend notices) when guacd dies instead of hanging on a dummy process.
log "Starting guacd on 0.0.0.0:4822 (log level: ${GUACD_LOG_LEVEL})"
exec guacd -b 0.0.0.0 -L "$GUACD_LOG_LEVEL" -f
