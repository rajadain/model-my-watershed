#!/bin/bash
# Run JS tests interactively
set -e

docker compose exec app ./node_modules/.bin/testem -f testem.json "$@"
