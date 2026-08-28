#!/bin/bash
# Get a shell in a container
# Usage: ./scripts/docker/shell.sh        # app container (default)
#        ./scripts/docker/shell.sh tiler  # tiler container

SERVICE=${1:-app}

docker compose exec $SERVICE /bin/bash
