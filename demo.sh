#!/usr/bin/env bash
# demo.sh — the on-stage / recording trigger script for the KubeCon lightning
# talk "Instrument Backstage with OpenTelemetry: From Zero Visibility to Full
# Traces in Minutes."
#
# Story beats (see repo notes): BEFORE (nothing in Jaeger) -> flip on the one
# instrumentation file -> AFTER (real traces + a real scaffolder task, traced).
#
# Usage:
#   ./demo.sh [--slow] [--mode=compose|k8s]
#
#   --slow          Injects real network latency into Toxiproxy in front of
#                   Gitea, simulating "your git provider is having a bad day" —
#                   a real, traceable HTTP call, not an in-process sleep, so
#                   it shows up as a genuine wide span in Jaeger.
#   --mode=compose  Default. Assumes `docker compose` stack (see docker-compose.yml).
#   --mode=k8s      Not implemented yet in this repo.
#
# Requires: docker compose, curl, python3 (for tiny JSON parsing), a TTY
# (the script pauses between phases so a screen recording has clean cut points).
set -euo pipefail

SLOW=false
MODE=compose

for arg in "$@"; do
  case "$arg" in
    --slow) SLOW=true ;;
    --mode=compose) MODE=compose ;;
    --mode=k8s) MODE=k8s ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--slow] [--mode=compose|k8s]" >&2
      exit 1
      ;;
  esac
done

if [[ "$MODE" == "k8s" ]]; then
  echo "--mode=k8s isn't wired up in this repo yet — rerun with --mode=compose (the default)." >&2
  exit 1
fi

BACKEND_URL="http://localhost:7007"
JAEGER_URL="http://localhost:16686"
GRAFANA_URL="http://localhost:3001"
TOXIPROXY_URL="http://localhost:8474"

SLOW_LATENCY_MS=8000 # Toxiproxy injects this much real latency on the Gitea fetch

banner() {
  echo
  echo "════════════════════════════════════════════════════════════════"
  echo "  $1"
  echo "════════════════════════════════════════════════════════════════"
}

pause() {
  echo
  read -r -p "   > press enter to continue..." _ || true
  echo
}

get_token() {
  curl -s "$BACKEND_URL/api/auth/guest/refresh" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['backstageIdentity']['token'])"
}

wait_for_backend() {
  echo "Waiting for backend at $BACKEND_URL ..."
  for _ in $(seq 1 60); do
    if curl -s -o /dev/null "$BACKEND_URL/api/auth/guest/refresh"; then
      echo "  backend is up."
      return 0
    fi
    sleep 1
  done
  echo "Backend never came up after 60s." >&2
  exit 1
}

banner "Bringing up the stack (Gitea, Toxiproxy, Collector, Jaeger, Prometheus, Grafana, backend)"
# Backend boots with instrumentation OFF from the very first start — otherwise
# it would emit a few startup traces before the BEFORE phase below even runs.
OTEL_SDK_DISABLED=true docker compose up -d --build
wait_for_backend

echo "Setting up the real git provider (Gitea + Toxiproxy)..."
"$(dirname "$0")/scripts/seed-gitea.sh"

# Always start from a clean, fast state regardless of how the last run ended.
curl -s -X DELETE "$TOXIPROXY_URL/proxies/gitea/toxics/latency_downstream" >/dev/null 2>&1 || true

banner "BEFORE: telemetry disabled"
echo "Backend already started with OTEL_SDK_DISABLED=true (NodeSDK's own standard kill switch)."

TOKEN=$(get_token)
echo
echo "curl $BACKEND_URL/api/catalog/entities   (instrumentation OFF)"
curl -s -o /dev/null -w "  -> HTTP %{http_code}\n" -H "Authorization: Bearer $TOKEN" \
  "$BACKEND_URL/api/catalog/entities"
echo
echo "Check Jaeger now — there should be no 'backstage-backend' service listed:"
echo "  $JAEGER_URL/search"
pause

banner "THE ONE FILE: app/packages/backend/src/instrumentation.ts"
echo "(cut to the editor here — ~35 lines, no Backstage core code touched)"
pause

banner "Flipping it on"
OTEL_SDK_DISABLED=false docker compose up -d --force-recreate backend
wait_for_backend
pause

banner "AFTER: telemetry enabled"
TOKEN=$(get_token)
for i in 1 2 3; do
  echo "curl $BACKEND_URL/api/catalog/entities   (#$i)"
  curl -s -o /dev/null -w "  -> HTTP %{http_code}\n" -H "Authorization: Bearer $TOKEN" \
    "$BACKEND_URL/api/catalog/entities"
done

banner "Triggering a real scaffolder task"
if [[ "$SLOW" == true ]]; then
  echo "Your git provider is having a bad day — injecting ${SLOW_LATENCY_MS}ms of real"
  echo "network latency into Toxiproxy (the same kind of tool used for chaos engineering)."
  curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"type\":\"latency\",\"attributes\":{\"latency\":$SLOW_LATENCY_MS}}" \
    "$TOXIPROXY_URL/proxies/gitea/toxics" >/dev/null
fi

# Retries a couple of times — right after a backend restart there's a brief
# window where guest-auth signing keys aren't ready yet and this 400s/500s.
TASK_ID=""
for attempt in 1 2 3; do
  TASK_ID=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"templateRef":"template:default/example-nodejs-template","values":{"name":"demo-service"}}' \
    "$BACKEND_URL/api/scaffolder/v2/tasks" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || true)
  [[ -n "$TASK_ID" ]] && break
  echo "  task creation attempt $attempt didn't return an id yet, retrying..."
  TOKEN=$(get_token)
  sleep 2
done
if [[ -z "$TASK_ID" ]]; then
  echo "Failed to create the scaffolder task after 3 attempts." >&2
  exit 1
fi
echo "Task ID: $TASK_ID"

echo "Polling task status..."
STATUS="open"
while [[ "$STATUS" != "completed" && "$STATUS" != "failed" ]]; do
  sleep 1
  STATUS=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "$BACKEND_URL/api/scaffolder/v2/tasks/$TASK_ID" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
  echo "  status: $STATUS"
done

banner "See it live"
echo "A single trace here can have hundreds of spans — Backstage's own internal"
echo "bookkeeping (DB writes, event logging) for every task step. Don't try to"
echo "explain all of them. Point at ONE: the 'GET toxiproxy' span."
echo "That's the real outbound call to your git provider — with --slow it's the"
echo "one wide bar that obviously stands out in the waterfall."
echo

FLUSH_WAIT=6
if [[ "$SLOW" == true ]]; then
  FLUSH_WAIT=$(( (SLOW_LATENCY_MS / 1000) + 6 ))
fi
echo "Waiting ${FLUSH_WAIT}s for the task to fully finish and the collector to flush..."
sleep "$FLUSH_WAIT"

if [[ "$SLOW" == true ]]; then
  curl -s -X DELETE "$TOXIPROXY_URL/proxies/gitea/toxics/latency_downstream" >/dev/null 2>&1 || true
fi

TRACE_ID=$(python3 -c "
import urllib.request, json, urllib.parse
# Both server.address and the method are needed — undici also emits a tiny
# tcp.connect sub-span carrying the same server.address tag, which would
# otherwise win a 'most recent' tie-break over the actual GET request span.
tags = urllib.parse.quote(json.dumps({'server.address': 'toxiproxy', 'http.request.method': 'GET'}))
url = f'$JAEGER_URL/api/traces?service=backstage-backend&tags={tags}&limit=1'
data = json.load(urllib.request.urlopen(url)).get('data', [])
print(data[0]['traceID'] if data else '')
" || true)

if [[ -n "$TRACE_ID" ]]; then
  echo "Direct link to THIS scaffolder run's trace (not the generic search page):"
  echo "  $JAEGER_URL/trace/$TRACE_ID"
else
  echo "Couldn't look up the exact trace ID automatically — use the search page:"
  echo "  $JAEGER_URL/search?service=backstage-backend"
fi
echo
echo "Grafana — scaffolder/catalog route latency dashboard:"
echo "  $GRAFANA_URL/d/backstage-otel-demo/backstage-otel-demo"
echo
echo "Done."


