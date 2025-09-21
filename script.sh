#!/bin/bash
set -e

ACTION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR" || exit 1

case "$ACTION" in
  start)
    find . -name docker-compose.yml -execdir docker compose up -d \;
    ;;
  stop)
    find . -name docker-compose.yml -execdir docker compose down \;
    ;;
  update)
    find . -name docker-compose.yml -execdir bash -c 'docker compose down && docker compose pull && docker compose up -d' \;
    ;;
  *)
    echo "Usage: $0 {start|stop|update}"
    exit 1
    ;;
esac
