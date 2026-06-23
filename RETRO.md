## Action Tracker

Items from retrospectives that need resolution. Every item must have a GitHub
issue or be explicitly closed with a reason.

| # | Action | Source | GitHub | Status | Notes |
|---|--------|--------|--------|--------|-------|
| 1 | Onboard 16 tag-blocked tenants once DD secrets are tagged `Environment=production` | Retro v0.1.0 | #5 | OUT-OF-REPO | Blocked on FCS applying secret tags (account-level IAM, not this repo). Tracked in `terraform/tenants.pending.md`. Gates ROADMAP P1. |
| 2 | Add self-review checklist item — wire Datadog `template_variable` into query scopes | Retro v0.1.0 (PR #4, recurred PR #8) | #6 | Closed | Added "Datadog dashboard conventions" to CLAUDE.md (PR #9) |

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

- [ ] Onboard 16 tag-blocked tenants — Action Tracker #1 (GitHub #5) — OUT-OF-REPO
- [x] Datadog template_variable self-review checklist item — Action Tracker #2 (GitHub #6) — resolved: CLAUDE.md "Datadog dashboard conventions" (PR #9)
- [x] Validate Bedrock anomaly monitor baseline — ROADMAP P3 — resolved in v0.1.1: the anomaly monitor wedged in Alert on a sparse model (ftc opus-4-8) that stopped emitting and re-paged hourly. Anomaly detection can't work on intermittent near-zero series, so `bedrock_invocations_drop` was removed entirely (redundant with the latency monitor).

<!-- Milestone retro entry template:
## <milestone> — <date>
**Quality**: N/5 · **What went well**: … · **Lessons**: … · **Actions**: → tracker
-->
