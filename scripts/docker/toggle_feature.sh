#!/bin/bash
# Toggle feature flags
# Usage: ./scripts/docker/toggle_feature.sh subbasin
#        ./scripts/docker/toggle_feature.sh clear
set -e

usage() {
    echo "$(basename "${0}") [OPTION]
    Toggle feature flags

    Options:
    subbasin     Sub-basin modeling
    clear        Clear all features
    "
}

case "$1" in
    subbasin)
        docker compose exec app sh -c 'echo -n "subbasin " >> /tmp/features'
        echo "Enabled subbasin feature. Restart app to apply."
        ;;
    clear)
        docker compose exec app sh -c 'echo -n "" > /tmp/features'
        echo "Cleared all features. Restart app to apply."
        ;;
    *)
        usage
        ;;
esac
