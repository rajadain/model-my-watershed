#!/bin/bash
# Run yarn commands
# Usage: ./scripts/docker/yarn.sh install
#        ./scripts/docker/yarn.sh add <package>
set -e

docker compose exec app yarn "$@"
