# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Removed
- `bedrock_invocations_drop` throughput-collapse monitor (all 7 orgs). Anomaly detection can't work on sparse/intermittent model traffic — it wedged in Alert on a model that stopped emitting and re-paged hourly. Redundant with `bedrock_invocation_latency_high`.

### Added
- Infrastructure-health alerts (per tenant): istio mTLS cert-signing failures and dd-trace agent telemetry-send failures — surfaced by a 2-day ftc error review that traced an unalerted istio control-plane incident.
- App Health dashboard: tightened the genuine-error filter to exclude istio/envoy/dd-agent infra noise (90,194 raw 'errors' → 1 real app error over 2 days in ftc).
- App Health dashboard: surface genuine errors by content (excluding ddtrace span-dump noise), top error-producing services, and a live error-log stream — replacing the unreliable status:error widgets.
- Per-tenant Datadog Ingest & Usage dashboard (log/APM ingest by service, hosts/containers, synthetics runs) to catch runaway log producers before they become a billing problem.
- Per-tenant Edge & Request Health dashboard (ALB status codes + istio ingress-gateway hits/errors/latency), rolled out to the 7 enabled orgs.
- Per-tenant USAi App Health & Errors dashboard (log-based errors + APM latency/throughput for chat/api/console/pipelines/embedding-proxy), rolled out to the 7 enabled orgs.
- Per-tenant model-backend triage dashboard (Bedrock metrics + Azure OpenAI log signals), rolled out to the 7 enabled tenant orgs.
