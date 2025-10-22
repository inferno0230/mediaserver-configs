#!/bin/bash
set -e

ACTION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/media/backup"
MAX_BACKUPS=5

cd "$SCRIPT_DIR" || exit 1

backup() {
    echo "Stopping all containers before backup..."
    find . -name docker-compose.yml -execdir docker compose down \;

    BACKUP_NAME="backup_$(date +'%Y%m%d%H%M%S').tar.gz"
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

    echo "Creating backup at $BACKUP_PATH..."
    # Create a compressed tarball of the relevant directories
    tar -czf "$BACKUP_PATH" arr jellyfin

    echo "Backup created: $BACKUP_PATH"
    
    # Keep only the 5 most recent backups
    echo "Cleaning up old backups..."
    find "$BACKUP_DIR" -type f -name "backup_*.tar.gz" | sort -r | sed -e "1,${MAX_BACKUPS}d" | xargs rm -f

    echo "Old backups cleaned. Keeping only the 5 most recent backups."
    find . -name docker-compose.yml -execdir docker compose up -d \;
}

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
  backup)
    backup
    ;;
  *)
    echo "Usage: $0 {start|stop|update|backup}"
    exit 1
    ;;
esac
