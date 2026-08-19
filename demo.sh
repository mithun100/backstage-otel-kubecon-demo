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
#   --slow          Bumps the scaffolder's simulated-work step to a long,
#                   obvious delay, so the trace waterfall shows a visible
#                   bottleneck to point at.
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

WAIT_SECONDS=1
if [[ "$SLOW" == true ]]; then
  WAIT_SECONDS=15
fi

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

banner "Bringing up the stack (Collector, Jaeger, Prometheus, Grafana, backend)"
# Backend boots with instrumentation OFF from the very first start — otherwise
# it would emit a few startup traces before the BEFORE phase below even runs.
OTEL_SDK_DISABLED=true docker compose up -d --build
wait_for_backend

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

banner "Triggering a real scaffolder task (waitSeconds=$WAIT_SECONDS)"
TASK_ID=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"templateRef\":\"template:default/example-nodejs-template\",\"values\":{\"name\":\"demo-service\",\"waitSeconds\":$WAIT_SECONDS}}" \
  "$BACKEND_URL/api/scaffolder/v2/tasks" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
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
echo "Jaeger — trace waterfall for this run:"
echo "  $JAEGER_URL/search?service=backstage-backend"
echo
echo "Grafana — scaffolder/catalog route latency dashboard:"
echo "  $GRAFANA_URL/d/backstage-otel-demo/backstage-otel-demo"
echo
echo "Done."
