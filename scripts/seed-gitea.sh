#!/usr/bin/env bash
# One-time, idempotent setup for the "real git provider" story: creates the
# Gitea admin user, a real repo (auto-init — a genuine initial commit, not a
# fake file), and the Toxiproxy proxy that sits in front of Gitea. Safe to
# re-run; skips anything that already exists.
set -euo pipefail

GITEA_URL="http://localhost:3002"
TOXIPROXY_URL="http://localhost:8474"
GITEA_USER="demo-admin"
GITEA_PASS="demo-password-123"
GITEA_EMAIL="demo-admin@example.com"
REPO_NAME="demo-service-template"

echo "Waiting for Gitea..."
for _ in $(seq 1 60); do
  curl -s -o /dev/null "$GITEA_URL/api/v1/version" && break
  sleep 1
done

if curl -s -u "$GITEA_USER:$GITEA_PASS" "$GITEA_URL/api/v1/user" | grep -q '"login"'; then
  echo "Gitea admin user already exists."
else
  echo "Creating Gitea admin user..."
  docker exec -u git gitea gitea admin user create \
    --username "$GITEA_USER" --password "$GITEA_PASS" --email "$GITEA_EMAIL" \
    --admin --must-change-password=false
fi

if curl -s -u "$GITEA_USER:$GITEA_PASS" "$GITEA_URL/api/v1/repos/$GITEA_USER/$REPO_NAME" | grep -q '"id"'; then
  echo "Repo '$REPO_NAME' already exists."
else
  echo "Creating real repo '$REPO_NAME' (auto-init — a genuine initial commit)..."
  curl -s -u "$GITEA_USER:$GITEA_PASS" -X POST -H "Content-Type: application/json" \
    -d "{\"name\":\"$REPO_NAME\",\"auto_init\":true,\"readme\":\"Default\",\"private\":false}" \
    "$GITEA_URL/api/v1/user/repos" >/dev/null
fi

# catalog-info.yaml so the scaffolder's final step can really register this
# repo as a Catalog component (not just fetch a file from it).
if curl -s -u "$GITEA_USER:$GITEA_PASS" \
  "$GITEA_URL/api/v1/repos/$GITEA_USER/$REPO_NAME/contents/catalog-info.yaml" | grep -q '"name"'; then
  echo "catalog-info.yaml already exists in the repo."
else
  echo "Adding catalog-info.yaml to the repo (for a real catalog:register step)..."
  CATALOG_INFO_B64=$(printf '%s\n' \
    'apiVersion: backstage.io/v1alpha1' \
    'kind: Component' \
    'metadata:' \
    '  name: demo-service-template' \
    '  description: Registered by the scaffolder demo from a real Gitea repo' \
    'spec:' \
    '  type: service' \
    '  owner: user:guest' \
    '  lifecycle: experimental' \
    | base64 | tr -d '\n')
  curl -s -u "$GITEA_USER:$GITEA_PASS" -X POST -H "Content-Type: application/json" \
    -d "{\"content\":\"$CATALOG_INFO_B64\",\"message\":\"Add catalog-info.yaml\",\"branch\":\"main\"}" \
    "$GITEA_URL/api/v1/repos/$GITEA_USER/$REPO_NAME/contents/catalog-info.yaml" >/dev/null
fi

echo "Waiting for Toxiproxy..."
for _ in $(seq 1 30); do
  curl -s -o /dev/null "$TOXIPROXY_URL/version" && break
  sleep 1
done

if curl -s "$TOXIPROXY_URL/proxies/gitea" | grep -q '"name"'; then
  echo "Toxiproxy proxy already exists."
else
  echo "Creating Toxiproxy proxy -> gitea:3000..."
  curl -s -X POST -H "Content-Type: application/json" \
    -d '{"name":"gitea","listen":"0.0.0.0:8080","upstream":"gitea:3000","enabled":true}' \
    "$TOXIPROXY_URL/proxies" >/dev/null
fi

# Baseline latency, always on — represents realistic "call a real external
# git provider over the network" time (X). demo.sh --slow stacks an
# additional, much larger toxic on top (X+Y) for the outage story, so the
# contrast between a normal and a degraded call is dramatic and relatable,
# not just "microseconds vs seconds".
if curl -s "$TOXIPROXY_URL/proxies/gitea/toxics/baseline_latency" | grep -q '"name"'; then
  echo "Baseline latency toxic already present."
else
  echo "Adding baseline latency toxic (~500ms, simulating a real network hop)..."
  curl -s -X POST -H "Content-Type: application/json" \
    -d '{"name":"baseline_latency","type":"latency","attributes":{"latency":500,"jitter":100}}' \
    "$TOXIPROXY_URL/proxies/gitea/toxics" >/dev/null
fi

echo "Gitea + Toxiproxy ready. Real repo: $GITEA_URL/$GITEA_USER/$REPO_NAME"
