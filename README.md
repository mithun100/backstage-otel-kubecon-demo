# Instrument Backstage with OpenTelemetry

Demo repo for the KubeCon co-located lightning talk **"Instrument Backstage
with OpenTelemetry: From Zero Visibility to Full Traces in Minutes."**

**The story in one sentence:** a stock Backstage backend has zero telemetry —
adding one ~35-line file gives you full traces and metrics for the catalog and
scaffolder, with no changes to Backstage's own code.

## Quickstart

```bash
git clone <this-repo>
cd backstage-instrumentation
./demo.sh
```

That's it — one command builds the backend image, brings up the whole
observability stack (Collector, Jaeger, Prometheus, Grafana, plus a real Gitea
+ Toxiproxy pair), seeds a real git repo, and walks through the before/after
story end-to-end, pausing at a few points so you can look around.

Run `./demo.sh --slow` to also inject real network latency into the "git
provider" call, producing an obvious, wide bottleneck span in the trace
waterfall.

Requires: Docker Desktop (or compatible), `curl`, `python3`. First run pulls
~6 images and builds the backend — subsequent runs are much faster thanks to
Docker layer caching.

## The story, and how this repo proves it

| Beat | What it maps to |
|---|---|
| "Backstage has zero telemetry by default" | `demo.sh` boots the backend with `OTEL_SDK_DISABLED=true` and shows Jaeger has no `backstage-backend` service |
| "One file fixes it — no core code touched" | [app/packages/backend/src/instrumentation.ts](app/packages/backend/src/instrumentation.ts) |
| "Now every request is traced" | `demo.sh` flips tracing on, curls the catalog, real `trace_id`/`span_id` appear immediately |
| "Here's a real, relatable ops problem" | The scaffolder fetches a file from a **real, self-hosted Gitea repo** through **Toxiproxy** (a real chaos-engineering fault-injection proxy). `--slow` injects real latency, simulating "your git provider is having a bad day" — and you can *see* it, in one specific trace, rather than guess |
| "Vendor-neutral, and it's not just traces" | OTel Collector → Jaeger (traces) + Prometheus/Grafana (metrics). No proprietary backend |

## Repo layout

```
app/                            Scaffolded Backstage app (@backstage/create-app)
  packages/backend/src/instrumentation.ts   ← THE file. ~35 lines.
  packages/backend/Dockerfile               Production image; wires instrumentation via --require
  app-config.docker.yaml                    Container config overlay (SQLite, allow-lists, etc.)
  examples/template/template.yaml           Scaffolder template used by the demo

docker-compose.yml               The whole stack: backend, Gitea, Toxiproxy,
                                  Collector, Jaeger, Prometheus, Grafana
collector-config.yaml            OTel Collector: OTLP in, Jaeger + Prometheus out
prometheus.yml                   Scrapes the Collector's metrics endpoint
grafana/                         Auto-provisioned datasource + dashboard
scripts/seed-gitea.sh            Idempotent: creates Gitea admin user, a real
                                  repo (auto-init), and the Toxiproxy proxy
scripts/scenarios/               One command per failure scenario (see below)
demo.sh                          The whole story, scripted and reproducible
```

## Running things manually

```bash
docker compose up -d --build      # bring up the whole stack
./scripts/seed-gitea.sh            # idempotent — safe to re-run
docker compose down                # tear down (add -v to also wipe Gitea's data)
```

Useful URLs once the stack is up:
- Backstage: http://localhost:7007
- Jaeger UI: http://localhost:16686
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3001
- Gitea (the real git server): http://localhost:3002
- Toxiproxy admin API: http://localhost:8474

### Finding the interesting trace in Jaeger

A single scaffolder-task trace can have hundreds of spans — Backstage's own
internal bookkeeping (DB writes, scheduled task logging). Don't try to explain
all of them on stage. Two ways to find the one that matters:

1. Let `demo.sh` do it — it prints a **direct link** to the exact trace it
   just triggered.
2. Manually: go to `http://localhost:16686/search`, set **Service** =
   `backstage-backend` and **Min Duration** = `3s`, click **Find Traces**.
   The one wide span is the real outbound call to Gitea (via Toxiproxy).
   Click it — its tags include `url.full` (the real repo path) and
   `server.address: toxiproxy`, proving it's a genuine network call, not a
   fake sleep.

## Live demo: step by step

Run everything from the repo root. Each step lists what you should see; if
you're ever unsure what's active, run `./scripts/scenarios/status.sh`.

### Step 0 — Pre-flight

```bash
git branch --show-current          # expect: main
docker info >/dev/null && echo "docker OK"
```

**Check:** prints `main` and `docker OK`. If Docker fails, start Docker Desktop.

### Step 1 — Start the stack and run the scripted story

```bash
./demo.sh
```

Press **Enter** at each pause. **Check:**
- BEFORE: http://localhost:16686 lists **no** `backstage-backend` service.
- AFTER: the catalog curls return `HTTP 200`.
- The scaffolder task polls to `status: completed`.
- The printed Jaeger link opens a single `GET` span of about **0.5 s**.

### Step 2 — Good case, from the UI

1. Open http://localhost:7007 and sign in as **Guest**.
2. **Create** → **Example Node.js Template** → type any name → **Review** → **Create**.
3. In Jaeger: Service `backstage-backend`, **Min Duration** `300ms`, **Find Traces**.

**Check:** all 4 steps go green. Jaeger shows a `GET` trace (1 span, ~0.5 s,
"Fetch From Git Provider") and a `POST` trace (~76 spans, ~0.5 s, "Register
In Catalog"). Ignore `TaskPipelineLoop` and `.../eventstream`: those are
background jobs and the browser's live progress stream.

### Step 3 — Slow case (degraded git provider)

```bash
./scripts/scenarios/slow-on.sh     # adds +8000 ms on top of the ~500 ms baseline
```

**Check:** the output lists both `baseline_latency` and `outage_latency`.

Trigger the template again from the UI. **Check:** "Fetch From Git Provider"
spins for about **9 s**. In Jaeger, set **Min Duration** to `5s`: the same `GET`
and `POST` traces now take about **8.5 s** instead of ~0.5 s.

```bash
./scripts/scenarios/slow-off.sh
```

**Check:** only `baseline_latency` is left.

### Step 4 — Network cut (nothing is listening)

```bash
./scripts/scenarios/down.sh        # disables the Toxiproxy proxy
```

**Check:** `enabled=False`.

Trigger the template again. **Check:** the task fails at "Fetch From Git
Provider" and the later steps show as skipped. In Jaeger, clear Min Duration,
set **Tags** to `error=true` and **Lookback** to `Last 15 minutes`:
- a `GET` error span under 1 ms with `ECONNREFUSED`, and
- a separate `tcp.connect` trace that **also** has an error.

```bash
./scripts/scenarios/up.sh
```

**Check:** `enabled=True`.

### Step 5 — Dependency crashed (the process is gone)

```bash
./scripts/scenarios/kill-gitea.sh  # stops the Gitea container
```

**Check:** `gitea: exited`.

Trigger the template again. **Check:** the task fails at the same step. Jaeger
`error=true` shows:
- a `GET` error with `ECONNRESET`, and
- a separate `tcp.connect` trace with **no** error (Toxiproxy accepted the
  connection; Gitea behind it was gone).

That `tcp.connect` difference is how you tell a network cut from a crashed
dependency. The two spans are separate traces, matched by timestamp, not
parent and child.

```bash
./scripts/scenarios/revive-gitea.sh
```

**Check:** `gitea: running`.

### Step 6 — Reset before the next run

```bash
./scripts/scenarios/normal.sh
```

**Check:** Gitea running, `enabled=True`, and only `baseline_latency` active.

**Grafana** (http://localhost:3001): panels use a rolling 5-minute window, so
trigger a task just before switching to it or the graphs will look empty.

## Known limitations (flagged, not hidden)

- **`yarn start` at the repo root doesn't load instrumentation.** There's a
  genuine conflict between Node's `--experimental-strip-types` and
  `backstage-cli repo start`'s internal dev-reload worker threads. This only
  affects that one local-dev convenience command — it does not affect the
  Docker/compose path the demo actually uses. `yarn workspace backend start`
  (backend alone) works fine for local dev tracing.
- **Kubernetes manifests (`k8s/`) are not implemented yet.** `demo.sh` accepts
  `--mode=k8s` for forward-compatibility but exits with a clear message if used.
- **`app-config.docker.yaml` intentionally uses in-memory SQLite**, not the
  Postgres `app-config.production.yaml` expects — this keeps the on-stage
  stack limited to the observability components, not a production deployment.
  Swap configs for a real deployment.
- **Guest auth is deliberately relaxed** (`dangerouslyAllowOutsideDevelopment: true`)
  and **the Gitea/Toxiproxy host is explicitly allow-listed** for `fetch:plain:file`
  (real SSRF protection, scoped down rather than disabled). Both are documented
  inline in `app-config.docker.yaml`. Auth/RBAC hardening is out of scope for
  this demo (see the original spec).
- First `docker compose up --build` pulls ~6 images and builds the backend —
  budget a few extra minutes on a clean machine before the "under 10 minutes"
  claim holds; subsequent runs are fast (layer-cached).
