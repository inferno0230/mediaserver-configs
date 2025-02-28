#!/bin/bash

DOCKER_DIR=$(pwd)

for dir in "$DOCKER_DIR"/*; do
    if [[ -f "$dir/docker-compose.yml" ]]; then
        echo "Updating $(basename "$dir")..."
        (
            cd "$dir" || exit
            sudo docker compose pull
            sudo docker compose up -d
        )
    fi
done
sudo docker system prune -a -f

echo "All containers updated!"
