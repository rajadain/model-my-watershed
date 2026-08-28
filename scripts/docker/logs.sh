#!/bin/bash
# View logs for services
# Usage: ./scripts/docker/logs.sh        # all services
#        ./scripts/docker/logs.sh app    # app only
#        ./scripts/docker/logs.sh -f app # follow app logs

docker compose logs "$@"
