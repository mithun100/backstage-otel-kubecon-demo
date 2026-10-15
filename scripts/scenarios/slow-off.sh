#!/usr/bin/env bash
# Turns OFF the degraded-performance scenario started by slow-on.sh: removes
# only the outage_latency toxic. baseline_latency (the always-on X) is left
# untouched, so calls go back to the normal ~500ms, not 0ms.
set -euo pipefail

TOXIPROXY_URL="http://localhost:8474"

curl -s -X DELETE "$TOXIPROXY_URL/proxies/gitea/toxics/outage_latency" >/dev/null 2>&1 || true

echo "Degraded performance OFF: back to baseline_latency only (~500ms)."
"$(dirname "$0")/status.sh"
