# Spec: Backstage + OpenTelemetry Lightning Talk Demo

## Context for the agent
You are building a demo repo for a 10-minute KubeCon co-located lightning talk titled
**"Instrument Backstage with OpenTelemetry: From Zero Visibility to Full Traces in Minutes."**
The presenter has no prior Backstage experience — the repo must be turnkey and reproducible
with no manual UI clicking beyond what's scripted. Optimize for reliability on stage over
cleverness. Open source projects named in the accepted submission: Backstage, OpenTelemetry,
Jaeger, Prometheus, Kubernetes — the demo must credibly use all five.

## Goal
Produce a repo that proves this narrative on stage:
1. A stock Backstage backend has **zero telemetry** by default.
2. Adding **one instrumentation file** (no core code changes) enables full traces and
   metrics for the catalog, scaffolder, and plugin requests.
3. The presenter can show a live trace waterfall in Jaeger and metrics in Prometheus/Grafana
   within minutes of enabling it.

## Two deployment paths (build BOTH)
Provide two ways to run the demo so the presenter can choose based on stage conditions:
- **`docker-compose` path** — fastest, most reliable fallback for a laptop on unpredictable
  conference wifi. This is the primary on-stage path.
- **Kubernetes path (`k8s/`)** — because the submission names Kubernetes as an OSS project
  used. Provide manifests (or a Helm/Kustomize layout) to run Backstage + OTel Collector +
  Jaeger + Prometheus on a local cluster (kind or minikube). Include a one-command
  `kind create cluster` + `kubectl apply -k k8s/` bring-up and a teardown script. Make clear
  in the README that this path is what backs the "Kubernetes" claim, and that compose is the
  low-risk stage fallback.

## Deliverables (in order of build)

### 1. `app/` — a scaffolded Backstage instance
- Use `npx @backstage/create-app@latest` to generate the base app (name it `otel-demo`).
- Do NOT hand-write Backstage internals — use the official scaffolder, then modify only
  what's listed below.
- Add one example catalog entity (`catalog-info.yaml`) and keep the default example
  software template so `scaffolder` has something real to execute.

### 2. `app/packages/backend/src/instrumentation.ts` — the single instrumentation file
- Use `@opentelemetry/sdk-node`, `@opentelemetry/auto-instrumentations-node`,
  `@opentelemetry/exporter-trace-otlp-http`, `@opentelemetry/exporter-metrics-otlp-http`,
  and `@opentelemetry/resources` / `semantic-conventions` for service name.
- Export a NodeSDK instance, call `.start()` at the top of the file (side-effect on import).
- Point OTLP exporters at `http://localhost:4318` (Collector HTTP receiver) by default,
  overridable via `OTEL_EXPORTER_OTLP_ENDPOINT` — in Kubernetes this becomes the Collector
  service DNS name.
- Set `service.name = "backstage-backend"` via resource attributes.
- Add a code comment block explaining this is the ONLY file needed — it is the punchline
  of the talk, so keep it minimal (~40–60 lines).

### 3. Wire-up (no core Backstage code changes)
- Modify `app/packages/backend/package.json` start script to preload the instrumentation
  file via Node's `--require` (compiled JS) or `--import` for ESM — verify against the
  installed Backstage version's actual backend entrypoint before wiring, since Backstage's
  backend bootstrapping has changed across versions. Flag it rather than guessing if it
  doesn't match.
- Confirm instrumentation loads BEFORE any Backstage backend module is required.

### 4. Observability backend — shared config, two deployments
Collector receives OTLP (grpc 4317 + http 4318), exports traces to Jaeger and metrics to
Prometheus. Jaeger for trace visualization; Prometheus scraping the collector; optional
Grafana dashboard for scaffolder task duration + catalog refresh duration.
- `docker-compose.yml` + `collector-config.yaml` for the compose path.
- `k8s/` manifests for the same four components on kind/minikube, with the Collector as a
  Service the Backstage pod points at via `OTEL_EXPORTER_OTLP_ENDPOINT`.
- Avoid port clashes with Backstage's 3000/7007; expose Jaeger UI 16686, Grafana 3001.

### 5. `demo.sh` — the on-stage trigger script
Single, re-runnable script that:
1. Prints "BEFORE: telemetry disabled", curls the catalog API (nothing in Jaeger when
   instrumentation is toggled off via env var).
2. Prints "AFTER: telemetry enabled".
3. Curls catalog `/entities` 2–3 times.
4. Triggers the example scaffolder template via `POST /api/scaffolder/v2/tasks`, polls to
   completion.
5. Prints Jaeger trace-search and Grafana dashboard URLs.
- `--slow` flag adds an artificial delay in one plugin call so the waterfall shows a
  visible bottleneck to point at.
- Detect or take a flag for compose vs k8s so URLs resolve correctly in both.

### 6. `README.md`
- One-command quickstart for BOTH paths.
- "How this maps to the talk" section matching the CFP: blind-spot-by-default, the one
  file, key traces/metrics unlocked, where to send telemetry.
- Note total time-to-first-trace under 10 minutes on a clean clone (compose path); flag any
  step threatening that budget.

## Constraints
- Vendor-neutral: OTel Collector + Jaeger + Prometheus (+ optional Grafana) only — CNCF
  co-located audience, no proprietary backend.
- No live coding on stage — everything runs from scripts.
- Keep the instrumentation file genuinely minimal; brevity is the point.
- Flag rather than silently work around any Backstage-version mismatch with the `--require`
  approach.

## Out of scope
- Production-hardening the Collector (sampling, retries, security).
- Auth/RBAC on Backstage.
- Plugin development beyond the stock example template.