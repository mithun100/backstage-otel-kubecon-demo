/**
 * OpenTelemetry instrumentation for the Backstage backend.
 *
 * THIS IS THE ONLY FILE THIS TALK IS ABOUT. No Backstage core code is
 * modified — this module is preloaded via Node's `--require` flag (see
 * packages/backend/package.json) so `sdk.start()` runs and patches Node's
 * http/Express/etc. internals BEFORE any Backstage backend module is
 * required. Instrumentation must load first, or there's nothing left to wrap.
 *
 * Traces + metrics ship over OTLP/HTTP to the Collector, which fans them out
 * to Jaeger (traces) and Prometheus (metrics). The exporters below default to
 * http://localhost:4318 and are fully overridable via the standard
 * OTEL_EXPORTER_OTLP_ENDPOINT env var (with /v1/traces or /v1/metrics
 * appended automatically) — in Kubernetes this becomes the Collector
 * Service's DNS name instead.
 */
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-http';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'backstage-backend',
  }),
  traceExporter: new OTLPTraceExporter(),
  metricReaders: [
    new PeriodicExportingMetricReader({
      exporter: new OTLPMetricExporter(),
    }),
  ],
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();

// Flush pending spans/metrics on shutdown so nothing is lost mid-demo.
process.on('SIGTERM', () => {
  sdk.shutdown().finally(() => process.exit(0));
});

export default sdk;
