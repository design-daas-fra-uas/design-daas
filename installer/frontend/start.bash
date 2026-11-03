#!/bin/bash
set -e

FRONT_DIR="$(dirname "$0")/../../../design-daas-application-frontend"

cd "$FRONT_DIR"

docker-compose -f docker-compose-pve.yml up
