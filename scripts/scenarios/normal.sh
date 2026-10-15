#!/usr/bin/env bash
# Resets the stack to healthy, steady-state "normal load": Gitea container
# running, Toxiproxy proxy enabled, only the always-on baseline_latency
# toxic present (no outage_latency, no down/kill state left over). Run this
# between scenarios so each one starts from a known-good baseline.
set -euo pipefail

TOXIPROXY_URL="http://localhost:8474"

echo "Making sure the Gitea container is running..."
docker compose start gitea >/dev/null
for _ in $(seq 1 30); do
  curl -s -o /dev/null "http://localhost:3002/api/v1/version" && break
  sleep 1
done

echo "Making sure the Toxiproxy proxy is enabled (undoes scenarios/down.sh)..."
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"enabled":true}' "$TOXIPROXY_URL/proxies/gitea" >/dev/null

echo "Removing outage_latency toxic if present (undoes scenarios/slow-on.sh)..."
curl -s -X DELETE "$TOXIPROXY_URL/proxies/gitea/toxics/outage_latency" >/dev/null 2>&1 || true

echo "Making sure baseline_latency toxic is present (the always-on X)..."
if ! curl -s "$TOXIPROXY_URL/proxies/gitea/toxics/baseline_latency" | grep -q '"name"'; then
  curl -s -X POST -H "Content-Type: application/json" \
    -d '{"name":"baseline_latency","type":"latency","attributes":{"latency":500,"jitter":100}}' \
    "$TOXIPROXY_URL/proxies/gitea/toxics" >/dev/null
fi

echo "Normal load: Gitea up, proxy enabled, only baseline_latency (~500ms) active."
"$(dirname "$0")/status.sh"
