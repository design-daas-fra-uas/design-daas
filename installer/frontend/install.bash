#!/bin/bash

# Configurable variables
SERVICE_NAME=frontend
export DEBIAN_FRONTEND=noninteractive

# help message
usage() { echo "Usage: $0 [-r <folder>]" 1>&2; exit 1; }

# Read options
REPO_FOLDER=
FRONTEND_FOLDER=

while getopts ":r:f:" o; do
    case "${o}" in
        r)
            REPO_FOLDER=${OPTARG}
            ;;
        f)
            FRONTEND_FOLDER=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

# Bail if requirements are not met
if [ ! -d "$FRONTEND_FOLDER" ] ; then
    usage
fi

FRONTEND_FOLDER=$(realpath "$FRONTEND_FOLDER")

cd "$FRONTEND_FOLDER/" || exit 1

cat <<EOF > docker-compose-pve.yml
version: "3.3"
services:
  web:
    build:
      context: "."
      target: "server"
    container_name: "daas-frontend"
    restart: "always"
    # volumes:
    # - '/usr/src/app/node_modules'
    ports:
      - "127.0.0.1:5001:80"
EOF
docker-compose -f docker-compose-pve.yml build

# systemd unit
cat <<EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Design DaaS Frontend
After=docker.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$FRONTEND_FOLDER
ExecStart=/usr/bin/docker-compose -f docker-compose-pve.yml up
ExecStop=/usr/bin/docker-compose -f docker-compose-pve.yml down
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME.service
systemctl start $SERVICE_NAME.service

