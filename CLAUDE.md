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
