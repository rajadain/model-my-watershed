#!/bin/bash
# Run Celery worker interactively with debug output
set -e

docker compose stop celery

docker compose run --rm celery \
    celery -A 'mmw.celery:app' worker -l debug -n debug@%n
