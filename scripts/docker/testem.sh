#!/bin/bash
# Run JS tests interactively
set -e

docker compose exec -w /var/www/mmw/static app \
    /opt/app/node_modules/.bin/testem -f /opt/app/testem.json "$@"
