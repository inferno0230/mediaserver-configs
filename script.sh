#!/bin/bash
set -euo pipefail

ACTION="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="/media/backup"
BACKUP_DIR="$BACKUP_ROOT/stack"
BACKUP_IMAGE="debian:stable-slim"   # needs GNU tar for --exclude-caches
MAX_BACKUPS=5
NET_MAX_TRIES=60   # x5s = give up waiting after ~5 minutes
NET_PROBE="https://controlplane.tailscale.com"

cd "$SCRIPT_DIR"

wait_for_network() {
    echo "Waiting for DNS + internet..."
    local i
    for ((i = 1; i <= NET_MAX_TRIES; i++)); do
        if curl -fsS -o /dev/null --connect-timeout 3 --max-time 10 "$NET_PROBE"; then
            echo "Network OK."
            return 0
        fi
        echo "Network not ready (attempt $i/$NET_MAX_TRIES), retrying in 5s..."
        sleep 5
    done
    # Start anyway: compose holds the arr services until the vpn healthcheck passes.
    echo "WARNING: network still not ready, starting anyway." >&2
}

backup() {
    local name
    name="backup_$(date +'%Y%m%d%H%M%S').tar.gz"

    # tar runs in a throwaway container: some state (e.g. tailscale) is root-owned
    # and /media/backup is root-owned, so this avoids needing sudo. Pull it first so
    # a network problem fails before anything is stopped.
    docker pull -q "$BACKUP_IMAGE" >/dev/null

    echo "Stopping containers for a consistent backup..."
    docker compose down
    # Whatever happens from here on (tar failure, Ctrl-C), bring the stack back.
    trap 'echo "Restarting containers..."; docker compose up -d' EXIT

    echo "Creating $BACKUP_DIR/$name..."
    # Written to a temp name first so a failed run never leaves a truncated backup.
    docker run --rm \
        -v "$SCRIPT_DIR:/src:ro" -v "$BACKUP_ROOT:/backup" -w /src \
        -e NAME="$name" -e SUBDIR="${BACKUP_DIR#"$BACKUP_ROOT"/}" -e OWNER="$(id -u):$(id -g)" \
        "$BACKUP_IMAGE" bash -euc '
            out="/backup/$SUBDIR"
            mkdir -p "$out" && chown "$OWNER" "$out"
            tar -czf "$out/$NAME.partial" \
                --exclude-caches \
                --exclude="jellyfin/data/cache" \
                --exclude="jellyfin/data/config/data/transcodes" \
                --exclude="jellyfin/data/config/log" \
                --exclude="arr/data/*/logs" \
                --exclude="arr/data/*/logs.db*" \
                compose.yml common.env script.sh arr jellyfin
            mv "$out/$NAME.partial" "$out/$NAME"
            chown "$OWNER" "$out/$NAME"'
    echo "Backup created: $BACKUP_DIR/$name ($(du -h "$BACKUP_DIR/$name" | cut -f1))"

    echo "Pruning to the newest $MAX_BACKUPS backups..."
    find "$BACKUP_DIR" -maxdepth 1 -type f -name 'backup_*.tar.gz' -print0 \
        | sort -zr | tail -zn +$((MAX_BACKUPS + 1)) | xargs -0r rm -f
}

case "$ACTION" in
  start)
    wait_for_network
    docker compose up -d
    ;;
  stop)
    docker compose down --remove-orphans
    ;;
  update)
    # Pull while everything keeps running; up -d only recreates changed services.
    docker compose pull
    docker compose up -d --remove-orphans
    docker image prune -f
    ;;
  backup)
    backup
    ;;
  *)
    echo "Usage: $0 {start|stop|update|backup}" >&2
    exit 1
    ;;
esac
