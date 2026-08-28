#!/bin/bash
# Bundle JS and CSS static assets
# Usage: ./scripts/docker/bundle.sh
#        ./scripts/docker/bundle.sh --watch
#        ./scripts/docker/bundle.sh --debug
#        ./scripts/docker/bundle.sh --vendor
set -e

docker compose exec app ./bundle.sh "$@"
