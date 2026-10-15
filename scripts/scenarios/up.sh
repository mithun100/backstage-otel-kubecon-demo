#!/usr/bin/env bash
# Recovers from down.sh: re-enables the Toxiproxy proxy so calls to
# toxiproxy:8080 reach Gitea again (subject to whatever latency toxics are
# still configured — baseline_latency, and outage_latency if slow-on.sh is
# also active).
set -euo pipefail

TOXIPROXY_URL="http://localhost:8474"

curl -s -X POST -H "Content-Type: application/json" \
  -d '{"enabled":true}' "$TOXIPROXY_URL/proxies/gitea" >/dev/null

echo "Full outage OFF: Toxiproxy proxy re-enabled, calls reach Gitea again."
"$(dirname "$0")/status.sh"
