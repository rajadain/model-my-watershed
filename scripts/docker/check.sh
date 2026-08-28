#!/bin/bash
# Run flake8 linting
set -e

docker compose exec app flake8 /opt/app/apps --exclude migrations
