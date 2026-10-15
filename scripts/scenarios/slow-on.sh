#!/usr/bin/env bash
# Turns ON the degraded-performance scenario: stacks a large outage_latency
# toxic (default 8000ms) on top of the always-on baseline_latency (500ms),
# so real calls to Gitea through Toxiproxy take ~X+Y seconds instead of
# ~X. Mirrors the "degraded performance" class of real GitHub incidents
# (service reachable, but slow) — as opposed to scenarios/down.sh or
# scenarios/kill-gitea.sh, which simulate it being fully unreachable.
#
# Usage: ./slow-on.sh [latency_ms]
set -euo pipefail

TOXIPROXY_URL="http://localhost:8474"
OUTAGE_LATENCY_MS="${1:-8000}"

curl -s -X DELETE "$TOXIPROXY_URL/proxies/gitea/toxics/outage_latency" >/dev/null 2>&1 || true
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"name\":\"outage_latency\",\"type\":\"latency\",\"attributes\":{\"latency\":$OUTAGE_LATENCY_MS}}" \
  "$TOXIPROXY_URL/proxies/gitea/toxics" >/dev/null

echo "Degraded performance ON: +${OUTAGE_LATENCY_MS}ms stacked on top of the 500ms baseline."
"$(dirname "$0")/status.sh"
