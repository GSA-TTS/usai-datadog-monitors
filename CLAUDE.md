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

## Deployment / apply workflow

- **Apply to live orgs only *after* the PR merges to `main` — never live-first.**
  The live-first habit (apply to the 25 orgs, *then* open the PR) cost us twice
  across the v0.3.0 monitor PRs (#28/#29/#30/#31/#32; GitHub #34):
  - **Provider-orphan deferred-apply chain.** Monitors applied live while
    referencing `datadog.nsf`/`datadog.eeoc` providers that didn't exist on
    `main` until #32 merged — so any targeted apply from `main` errored on the
    orphaned providers, and #28–#31's live re-applies all had to batch behind
    #32. Applying only post-merge keeps `main` and the live state in lock-step:
    the providers a plan references always exist.
  - **Cross-PR file-append conflicts.** #28 and #29 both appended to
    `infra_monitors.tf` (and `CHANGELOG.md`) and collided the instant #28
    merged. (The CHANGELOG half of this is now handled by the fragment-file
    workflow below; the `.tf` half is avoided by not stacking live edits ahead
    of merge.)
  - The batched apply is fine as the *final* step: merge the PR(s), then run one
    `terraform apply` from `main` so live state matches reviewed source. For a
    pure refactor, a **zero-diff plan** from `main` is the proof the merge
    changed nothing live (see #33/PR #36).
  - When several monitor/dashboard PRs are genuinely interdependent (shared
    provider wiring, shared file), land them as one stack or merge the
    base-provider PR first — don't apply an interim state that only exists on a
    branch.

## CHANGELOG workflow

- **Don't edit the `### Added` list head in `CHANGELOG.md` directly — drop a
  fragment file in `changelog.d/`.** Every monitor/dashboard PR used to append
  to the same section head, so each PR three-way-conflicted with its siblings
  the instant one merged (four consecutive PRs — #29/#30/#31/#32 — paid that tax;
  GitHub #35). The collision is *section-local*: two PRs editing `### Added`
  collide, a PR editing `### Changed` does not. Per-PR fragment files never share
  a path, so they never conflict regardless of section. Name them
  `changelog.d/<pr-or-issue>-<slug>.<type>.md` where `<type>` is a lower-cased
  Keep a Changelog section (`added`/`changed`/`removed`/`fixed`/…); the body is
  the bullet text with no leading `- `. At release, `scripts/assemble-changelog.sh`
  folds them into `[Unreleased]` and deletes them (`--check` for a dry run). See
  `changelog.d/README.md`.

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
