#!/usr/bin/env bash
# Simulates a full, network-level outage: disables the Toxiproxy proxy
# itself, so Toxiproxy stops listening and every call to toxiproxy:8080
# fails immediately with a connection error (not a timeout). The Gitea
# container itself keeps running untouched — this is "the network path to
# your git provider is cut", the network-level twin of a real GitHub
# "we are investigating connectivity issues" incident.
#
# For "the git provider process itself crashed" instead, use kill-gitea.sh.
# To recover from this one, use up.sh.
set -euo pipefail

TOXIPROXY_URL="http://localhost:8474"

curl -s -X POST -H "Content-Type: application/json" \
  -d '{"enabled":false}' "$TOXIPROXY_URL/proxies/gitea" >/dev/null

echo "Full outage ON: Toxiproxy proxy disabled, all calls to the git provider fail fast (connection refused)."
"$(dirname "$0")/status.sh"
