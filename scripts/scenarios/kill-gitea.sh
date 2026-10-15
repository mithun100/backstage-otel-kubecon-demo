#!/usr/bin/env bash
# Simulates the git provider's process actually crashing (not just a
# network block): stops the real Gitea container. Toxiproxy stays up and
# listening, so calls now get a real upstream connection error from
# Toxiproxy's side (dial tcp gitea:3000: connect: connection refused),
# which is a different, more "real" failure mode than down.sh's instant
# proxy-level refusal — closer to a real GitHub "service is down" incident
# where the dependency itself, not just the network, is unavailable.
#
# To recover, use revive-gitea.sh.
set -euo pipefail

echo "Stopping the Gitea container (simulating the git provider process crashing)..."
docker compose stop gitea

echo "Gitea is down. Calls to the git provider will now fail with a real upstream connection error."
"$(dirname "$0")/status.sh"
