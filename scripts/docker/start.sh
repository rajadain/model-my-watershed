#!/bin/bash
# Start all services
set -e

docker compose up -d

echo "Services started. View logs with: docker compose logs -f"
echo "App available at: http://localhost:8000"
