#!/usr/bin/env bash
# Recovers from kill-gitea.sh: starts the Gitea container back up and waits
# for it to accept connections again.
set -euo pipefail

echo "Starting the Gitea container back up..."
docker compose start gitea

echo "Waiting for Gitea to come back up..."
for _ in $(seq 1 60); do
  curl -s -o /dev/null "http://localhost:3002/api/v1/version" && break
  sleep 1
done

echo "Gitea is back up."
"$(dirname "$0")/status.sh"
