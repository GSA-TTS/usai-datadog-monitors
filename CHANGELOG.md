# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Removed
- `bedrock_invocations_drop` throughput-collapse monitor (all 7 orgs). Anomaly detection can't work on sparse/intermittent model traffic — it wedged in Alert on a model that stopped emitting and re-paged hourly. Redundant with `bedrock_invocation_latency_high`.

### Added
- Onboarded 16 previously-blocked tenant orgs (ang, doc, doi, doli, dot, ed, fhfa, gsa, hhs, hud, ncua, opm, pc, sss, stateoig, usda) — total enabled: 23.
- Container OOMKilled crash-loop monitor (`event-v2 alert`, >=2 kills/10m) + "Container OOMKilled" section on Infra Health dashboard (event timeline + stream). Motivated by GSA api OOM-looping (51 kills/24h, 2026-07-09) with zero alerting.
- DocumentDB health-check monitor (DNS/reachability) + a DocumentDB section on the Infra Health dashboard (failure logs alongside cluster connections/CPU).
- docs/platform-infra-findings-2026-06.md: istio cert-signing outage + DocumentDB DNS findings for the platform team.
- App Health dashboard: show ACTUAL Postgres errors (top error messages + a live stream of failing query spans with @error.message and the SQL), not just a count. Sourced from postgres.query error spans. ftc: 100% are 'psycopg2.OperationalError: SSL SYSCALL error: EOF detected'.
- App Health dashboard: reworked the Postgres datastore section — commits-vs-rollbacks, rollback ratio %, and query-errors/rollback-duration. Replaces the single rollback-count widget that misleadingly labeled the normal SQLAlchemy read-only ROLLBACK pattern (~58% ratio, 0 errors) as 'failing transactions'.
- Infra Health dashboard: root-cert **days-until-expiry** countdown widget (color-coded), replacing the meaningless raw-epoch value.
- Per-tenant Service Mesh & Infra Health dashboard (istio Citadel cert signing, Pilot xDS, control-plane process health + the infra log signals excluded from App Health).
- Infrastructure-health alerts (per tenant): istio mTLS cert-signing failures and dd-trace agent telemetry-send failures — surfaced by a 2-day ftc error review that traced an unalerted istio control-plane incident.
- App Health dashboard: tightened the genuine-error filter to exclude istio/envoy/dd-agent infra noise (90,194 raw 'errors' → 1 real app error over 2 days in ftc).
- App Health dashboard: surface genuine errors by content (excluding ddtrace span-dump noise), top error-producing services, and a live error-log stream — replacing the unreliable status:error widgets.
- Per-tenant Datadog Ingest & Usage dashboard (log/APM ingest by service, hosts/containers, synthetics runs) to catch runaway log producers before they become a billing problem.
- Per-tenant Edge & Request Health dashboard (ALB status codes + istio ingress-gateway hits/errors/latency), rolled out to the 7 enabled orgs.
- Per-tenant USAi App Health & Errors dashboard (log-based errors + APM latency/throughput for chat/api/console/pipelines/embedding-proxy), rolled out to the 7 enabled orgs.
- Per-tenant model-backend triage dashboard (Bedrock metrics + Azure OpenAI log signals), rolled out to the 7 enabled tenant orgs.
