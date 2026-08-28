#!/bin/bash
# Run Django management commands
# Usage: ./scripts/docker/manage.sh migrate
#        ./scripts/docker/manage.sh shell
#        ./scripts/docker/manage.sh runserver 0.0.0.0:8000
set -e

ARGS=${*:-"help"}

# Sane defaults for runserver (match existing behavior)
if [[ $# -eq 1 ]] && [[ $1 == runserver ]]; then
    ARGS="runserver 0.0.0.0:8000"
fi

docker compose exec app python manage.py $ARGS
