#!/bin/bash
# Run the full test suite
set -e
set -x

# Run flake8 against Django codebase
if ! docker compose exec app flake8 /opt/app/apps --exclude migrations; then
    echo "flake8 check failed"
fi

# Run Django tests
docker compose exec app python manage.py test --noinput --exclude-tag=mapshed

# Run JS unit tests (unless skipped)
if [[ -z "${MMW_SKIP_JS_TESTS}" ]]; then
    docker compose exec app xvfb-run ./node_modules/.bin/testem -f testem.json ci "$@"
else
    echo "SKIPPING JS TESTS"
fi
