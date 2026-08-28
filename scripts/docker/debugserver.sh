#!/bin/bash
# Run Django dev server with auto-reload (foreground)
set -e

docker compose stop app

docker compose run --rm --service-ports app \
    gunicorn --reload --bind 0.0.0.0:8000 --workers 1 mmw.wsgi
