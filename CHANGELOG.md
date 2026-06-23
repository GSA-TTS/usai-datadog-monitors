# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Removed
- `bedrock_invocations_drop` throughput-collapse monitor (all 7 orgs). Anomaly detection can't work on sparse/intermittent model traffic — it wedged in Alert on a model that stopped emitting and re-paged hourly. Redundant with `bedrock_invocation_latency_high`.

### Added
- Per-tenant USAi App Health & Errors dashboard (log-based errors + APM latency/throughput for chat/api/console/pipelines/embedding-proxy), rolled out to the 7 enabled orgs.
- Per-tenant model-backend triage dashboard (Bedrock metrics + Azure OpenAI log signals), rolled out to the 7 enabled tenant orgs.
