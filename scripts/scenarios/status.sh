#!/usr/bin/env bash
# Prints the current state of every scenario toggle, so you always know
# what's active before/during a demo segment: Gitea container state,
# Toxiproxy proxy enabled/disabled, and which toxics are configured.
set -euo pipefail

TOXIPROXY_URL="http://localhost:8474"

echo "--- Gitea container ---"
# --all so a stopped container (kill-gitea.sh) still shows up instead of
# being silently omitted, which is the default `docker compose ps` behavior.
docker compose ps gitea --all --format '{{.Names}}: {{.State}} ({{.Status}})' 2>/dev/null \
  || echo "gitea: not found (is the stack up?)"

echo "--- Toxiproxy proxy ---"
curl -s "$TOXIPROXY_URL/proxies/gitea" | python3 -c "
import json, sys
try:
    p = json.load(sys.stdin)
    print(f\"gitea proxy: enabled={p.get('enabled')} listen={p.get('listen')} upstream={p.get('upstream')}\")
except Exception:
    print('gitea proxy: not found (has scripts/seed-gitea.sh run yet?)')
"

echo "--- Active toxics ---"
curl -s "$TOXIPROXY_URL/proxies/gitea/toxics" | python3 -c "
import json, sys
try:
    toxics = json.load(sys.stdin)
    if not toxics:
        print('(none)')
    for t in toxics:
        print(f\"  {t['name']}: {t['type']} {t['attributes']}\")
except Exception:
    print('(unable to read toxics)')
"
