## Action Tracker

Items from retrospectives that need resolution. Every item must have a GitHub
issue or be explicitly closed with a reason.

| # | Action | Source | GitHub | Status | Notes |
|---|--------|--------|--------|--------|-------|
| 1 | Onboard 16 tag-blocked tenants once DD secrets are tagged `Environment=production` | Retro v0.1.0 | #5 | Closed | Resolved PR #19: 16 tenants onboarded (gsai KMS-blocked, disa no SSO, aigov excluded by request) |
| 2 | Add self-review checklist item — wire Datadog `template_variable` into query scopes | Retro v0.1.0 (PR #4, recurred PR #8) | #6 | Closed | Added "Datadog dashboard conventions" to CLAUDE.md (PR #9) |
| 3 | Add stacked-PR pre-merge safety check to pipeline workflow | Retro v0.2.0 (PR #18) | #20 | Open | Detect stacked PRs and retarget child before merging base |
| 4 | Document `event-v2 alert` monitor graph limitation in CLAUDE.md | Retro v0.2.0 (PR #19) | #21 | Open | Pair event-v2 monitors with dashboard widgets for visual history |

## v0.1.0 — Multi-tenant model-backend monitoring (PRs #1–#4)

**Date**: 2026-06-22
**Scope**: Roll out Bedrock + Azure OpenAI monitors and a triage dashboard to 7
tenant Datadog orgs via a reusable module; move state to a shared S3 backend;
make the repo pipeline-ready.
**Tests at close**: n/a (IaC — gate is `terraform validate` + `fmt`, both green)

### What We Learned

**1. Empty Terraform state hides the real blast radius; querying live infra is the actual review.**
On PR #1 the plan read `0 to change, 0 to destroy`, but that was only because state
was empty — Terraform had no idea what already lived in the 7 orgs. The real
safety check was querying each org's live monitors via the API and confirming our
6 monitors didn't collide with the existing FCS-managed / synthetics / API
monitors. "Plan is clean" ≠ "plan is safe" when state is fresh.

**Action taken**: Closed — folded into practice this milestone (pre-apply live-API
diff was run for PR #1 and #4). No standing artifact needed; the lesson is captured
in this Insights section below.

**2. Remote state was set up reactively, after 42 resources were already live.**
PRs #1 (monitors) and #4-precursor (dashboards) were applied while state was still
local on the laptop — a real risk: losing it would orphan 42+ monitors and a
re-apply would duplicate them. PR #2 fixed it by migrating to the shared
`aigov-tenant-tfstate` S3 bucket, but the ordering meant a window of fragility.

**Action taken**: Closed — remote S3 backend shipped in PR #2; `terraform plan`
reports no drift. Future repos should establish the backend before the first apply.

**3. A static metric threshold can't express "collapse" across tenants with 4
orders of magnitude of traffic difference.**
The `bedrock_invocations_drop` monitor (`< 3 in 15m`) was calibrated to GSA prod
(~80/5m) and false-fired immediately in low-traffic tenants (ftc opus-4-8 ~2/hr).
Fixed by converting to a per-model anomaly alert (`agile`, 3σ, `direction=below`).

**Action taken**: Closed — anomaly monitor shipped (commit on `feat/bedrock-monitors`,
PR #1) and applied to all 7 orgs. Baseline-tuning follow-up is ROADMAP P3.

**4. A declared Datadog `template_variable` that isn't wired into query scopes is
silently decorative.**
PR #4's dashboard had a `modelid` picker that didn't filter anything because the
widget queries hardcoded `{*}`. Caught in code review, fixed with `{$modelid}`.

**Action taken**: Open — tracked in Action Tracker #2 (GitHub #6).

**5. The 16-tenant onboarding is blocked on out-of-repo secret tagging.**
Only 7 of 23 tenants are enabled; the rest can't have their DD keys read until the
`Environment=production` tag is applied to their secrets by the FCS team.

**Action taken**: OUT-OF-REPO — tracked in Action Tracker #1 (GitHub #5).

### Insights

- **Provider aliases can't `for_each`** — multi-org Datadog forced an explicit
  per-tenant block (aws alias → secret data sources → datadog alias → module call).
  Repetitive but unavoidable; generated programmatically to avoid hand-error.
- **Sourcing keys from Secrets Manager at plan time** beat juggling 14 `TF_VAR_`s
  and keeps secrets out of the shell/env.
- **Code review earned its keep on PR #4** — caught the decorative picker that
  `terraform validate` and live-rendering both passed. Schema-valid ≠ functional.
- **pipeline-ship's DOCS_ONLY classification** correctly skipped Test/Self-Review/
  Security on PR #3 with no false gates, and ran them fully on PR #4 (code change).

### Review Stats

| Metric | PR #1 | PR #2 | PR #3 | PR #4 | Total |
|--------|-------|-------|-------|-------|-------|
| Resources applied | 42 | 0 (state migrate) | 0 (docs) | 7 (+7 updated) | 49 |
| 🔴 Findings | 0 | 0 | 0 | 0 | 0 |
| 🟡 Findings | 1 (Azure new_group_delay) | 0 | 0 | 1 (modelid picker) | 2 |
| Findings fixed | 1 | 0 | 0 | 1 | 2 |
| Formal retro | backfilled | backfilled | yes | yes | — |

### Process Improvements Applied

**CLAUDE.md**: Added the pipeline-config block (default/pr_target=main, terraform
validate / fmt commands) in PR #3.
**Pipeline template**: Installed feature/bugfix/refactor templates (PR #3).
**Checklist**: Datadog template_variable wiring item proposed → tracked (#6).
**Skills**: None changed.

### Open Items

- [x] Onboard 16 tag-blocked tenants — Action Tracker #1 (GitHub #5) — resolved in v0.2.0 (PR #19)
- [x] Datadog template_variable self-review checklist item — Action Tracker #2 (GitHub #6) — resolved: CLAUDE.md "Datadog dashboard conventions" (PR #9)
- [x] Validate Bedrock anomaly monitor baseline — ROADMAP P3 — resolved in v0.1.1: the anomaly monitor wedged in Alert on a sparse model (ftc opus-4-8) that stopped emitting and re-paged hourly. Anomaly detection can't work on intermittent near-zero series, so `bedrock_invocations_drop` was removed entirely (redundant with the latency monitor).

## v0.2.0 — Full observability suite + 23-tenant rollout (PRs #7–#19)

**Date**: 2026-07-09
**Scope**: Expanded from 3 Bedrock monitors + 1 dashboard (v0.1.0) to a full
observability suite — 5 dashboards + 9 monitors per tenant — and rolled out to
23 orgs (from the original 7). Key additions: App Health, Edge/Request, Usage,
Infra Health dashboards; istio/dd-agent/DocumentDB/OOM monitors; deeper
Postgres insight; infrastructure noise filtering.
**Tests at close**: `terraform validate` + `fmt -check` green; `terraform plan`
clean across 23 orgs (285 resources total).

### What We Learned

**1. Anomaly detection is the wrong tool for sparse/intermittent metrics.**
The `bedrock_invocations_drop` anomaly monitor wedged in perpetual Alert when a
model (opus-4-8) stopped emitting entirely. With `count_default_zero`, the
absent series satisfies the anomaly condition and the recovery window never
evaluates. Removed in PR #7 (redundant with latency monitor).

**Action taken**: Closed — monitor removed PR #7; lesson recorded in CLAUDE.md
dashboard conventions ("source signals from what's actually populated").

**2. 90K "errors" were infrastructure noise, not app bugs.**
A 2-day ftc review (motivating PRs #11-#12) found that 99.999% of
`status:error` logs were istio cert-signing, envoy xDS, and dd-agent
telemetry failures. Only 1 genuine app error in 90,194. Led to the
`genuine_error_query` filter and the separate Infra Health dashboard.

**Action taken**: Closed — genuine_error_query + Infra Health dashboard shipped
(PRs #11-#13); infra monitors alert on the signals proactively (PR #12).

**3. Stacked PRs + `--delete-branch` auto-close the child.**
Merging PR #16 with `--delete-branch` silently closed stacked PR #17 (base
branch vanished). Recovery: rebase onto squash-merged main + reopen as #18.
The correct flow: retarget child to main BEFORE merging the base.

**Action taken**: Open — tracked in Action Tracker #3 (GitHub #20).

**4. `event-v2 alert` monitors don't render a historical graph.**
The OOM monitor (PR #19) works correctly but the Datadog UI shows a blank
graph on the monitor page. This is a platform limitation — containerd events
don't land in the logs index so log alerts can't see them either. The
workaround is pairing with dashboard event widgets.

**Action taken**: Open — tracked in Action Tracker #4 (GitHub #21).

**5. Secret naming is inconsistent across tenant accounts.**
The 16 newly-unblocked tenants revealed 3 naming patterns: `usai-<t>-shared-dd-*`
(most), `<t>-shared-dd-*` (aigov, gsai), and a non-standard profile (doli →
`aigov-doli`). Always `list-secrets` before assuming a pattern.

**Action taken**: Closed — documented in `tenants.pending.md`; the discovery
workflow (probe all accounts programmatically) is now the standard onboarding step.

**6. `trace.*.request.duration` reads in milliseconds despite metadata declaring seconds.**
Live ingress values are ~200-300 (ms), not hundreds of seconds. Mislabeling
caused initial dashboard SLO markers to be 1000x too tight.

**Action taken**: Closed — labels corrected to "ms" and markers set correctly
(1000ms = 1s) across all dashboards; documented in CLAUDE.md dashboard conventions.

### Insights

- **The genuine-error signal was hiding in plain sight** — once infra noise was
  filtered, the real app errors (Postgres SSL EOF, rate limiting) stood out clearly.
- **Datadog GovCloud template variables with `prefix`** already expand to include
  the prefix — `$service` becomes `service:*`. Writing `service:$service` produces
  `service:service:*` which matches nothing. Cost ~2h of debugging (PR #16).
- **TCP keepalives solve SSL EOF under NLB** — `pool_pre_ping` only validates at
  checkout, not mid-request. Connections idle during long streaming completions die
  at the NLB 350s timeout.
- **`terraform apply` before PR** works well for this repo — monitors are
  immediately useful and the PR is a record of what was applied, not a gate.

### Review Stats

| Metric | PRs #7-12 | PRs #13-16 | PR #18 | PR #19 | Total |
|--------|-----------|------------|--------|--------|-------|
| Resources applied | -7 (removed) +35 | +28 | +11 | +231 | 298 |
| 🔴 Findings | 0 | 0 | 0 | 0 | 0 |
| 🟡 Findings | 1 (template_var) | 1 (live_span) | 0 | 1 (note/threshold) | 3 |
| Findings fixed | 1 | 1 | 0 | 1 | 3 |

### Process Improvements Applied

**CLAUDE.md**: Added "Datadog dashboard conventions" section (PR #9) covering
template_variable wiring, env:production scoping, signal sourcing, duration units.
**Pipeline template**: No changes.
**Skills**: Stacked-PR caution added to pipeline-ship Step 2.5 (PR #18 retro).

### Open Items

- [ ] Document `event-v2 alert` graph limitation — Action Tracker #4 (GitHub #21)
- [ ] Add stacked-PR pre-merge check to pipeline workflow — Action Tracker #3 (GitHub #20)
- [x] Onboard blocked tenants — Action Tracker #1 (GitHub #5) — resolved: 16 tenants onboarded PR #19 (gsai KMS-blocked, disa no SSO, aigov excluded)

<!-- Milestone retro entry template:
## <milestone> — <date>
**Quality**: N/5 · **What went well**: … · **Lessons**: … · **Actions**: → tracker
-->
