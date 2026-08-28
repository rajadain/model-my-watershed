#!/bin/bash
# Run database migrations
set -e

docker compose exec app python manage.py migrate
