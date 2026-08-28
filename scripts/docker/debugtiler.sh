#!/bin/bash
# Run tiler with watch mode for development
set -e

docker compose stop tiler

docker compose run --rm --service-ports tiler npm run watch
