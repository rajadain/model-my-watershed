#!/bin/bash
# Bring up the local development environment (Docker flow) and make sure
# it's ready to browse at http://localhost:8000.
#
# Usage: ./scripts/server.sh
set -e

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
    echo "No .env file found; copying from .env.example"
    cp .env.example .env
fi

# rwd (Rapid Watershed Delineation) is optional for most local development
# (see CLAUDE.md), and its published image currently fails to pull on newer
# Docker/containerd versions (old manifest format). Skip it here, and start
# celery with --no-deps so it doesn't get pulled in anyway as a side effect
# of celery's dependency on it.
docker compose up -d --no-deps postgres redis app celery tiler geop

echo "Waiting for the app to accept connections..."
until docker compose exec -T app python -c "import socket; socket.create_connection(('localhost', 8000), 2)" 2>/dev/null; do
    sleep 1
done

docker compose exec app python manage.py migrate

echo ""
echo "Dev environment is up: http://localhost:8000"
echo "View logs with: docker compose logs -f"
echo "(rwd/watershed delineation was skipped; see CLAUDE.md if you need it)"
