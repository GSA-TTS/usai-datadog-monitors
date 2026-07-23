<!-- pipeline-config: managed by /pipeline-init -->
## Pipeline configuration

- default_branch: main
- pr_target_branch: main
- test_command: cd terraform && terraform validate
- lint_command:
- format_command: cd terraform && terraform fmt -check -recursive
- build_command:
- venv_path:
- changelog: keep-a-changelog
<!-- /pipeline-config -->

## Datadog dashboard conventions

Lessons baked in from PRs #4 and #8 (self-review checklist for any dashboard work):

- **Wire every `template_variable` into at least one widget query scope** (`{$var}`
  for metric queries, `service:(...)` / the var in `search_query` for log queries).
  A declared-but-unreferenced variable renders a picker that silently filters
  nothing. Caught twice in review (`$modelid` PR #4, `$service` PR #8).
- **Scope log widgets to `env:production`** so non-prod logs don't inflate counts —
  match the existing `dashboard.tf` Azure widgets.
- **Source signals from what's actually populated, not what "should" exist.**
  Verified in these orgs: errors live in LOGS (`status:error`), not APM
  span-error metrics (`trace.*.request.errors` are empty); edge latency comes from
  `trace.envoy.proxy.duration`, not `aws.applicationelb.target_response_time`
  (also empty). Probe with the metrics/query API before building.
- **`trace.*.request.duration` reads in milliseconds** despite the metric metadata
  declaring `unit: second` — live ingress values are ~200–300, which are ms, not
  hundreds of seconds. Label latency widgets "ms" and set SLO markers in ms
  (e.g. `y = 1000` for 1s).

## Datadog monitor conventions

Lessons baked in from PR #22 (self-review checklist for any monitor work):

- **Scope the notification handle to `{{#is_alert}}` / `{{#is_alert_recovery}}`,
  never bare.** A `${var.notification_channel}` handle placed as a trailing line
  (outside every conditional block) renders on Warn, Recovered, AND Triggered —
  so every state transition pings Slack. This shipped in the v0.1.0 monitors and
  flooded the ops channel across 23 orgs before it was caught (PR #22). Put the
  handle only where you want a page; warnings that shouldn't page get no handle.
- **Prefer error/latency RATES over absolute counts** for anything that spans
  tenants or models with very different traffic. `>5 errors in 5m` pages a 0.6%
  low-volume blip identically to a real 5.8% degradation; `(errors/invocations)
  * 100 > N` over a longer window does not. (Same lesson that removed
  `bedrock_invocations_drop` in v0.1.0 and reshaped `bedrock_server_errors` in
  PR #22.)
- **Add recovery-threshold hysteresis** (`critical_recovery` / `warning_recovery`)
  on any monitor whose metric hovers near the line, or it flaps Alert↔OK. Set
  recovery values clearly on the non-triggering side (below the trigger for a
  "greater than" monitor).
- **`event-v2 alert` monitors don't render a time-series graph** on the monitor
  page (Datadog UI limitation) — pair them with dashboard `event_timeline` /
  `event_stream` widgets for visual history. (GitHub #21.)
- **Any monitor with a handle-less warn tier must use `{{#is_alert_recovery}}`,
  never bare `{{#is_recovery}}`, around the notification handle.**
  `{{#is_recovery}}` fires on OK from *either* the alert OR the warning tier — so
  if `warning` is set with no handle (a deliberately quiet warn), a WARN→OK
  transition still renders the recovery block and pings the channel. That's the
  same asymmetric-noise flood class as the bare-handle bug (PR #22). Caught in
  code review on the CronJob monitor (PR #28). `{{#is_alert_recovery}}` fires only
  after a real (critical) page recovers. A monitor with no warn tier (e.g.
  `deployment_unavailable`) can use `{{#is_recovery}}` safely.
