# usai-datadog-monitors ROADMAP

## Priority Matrix

| Priority | Feature | Why | Milestone |
|----------|---------|-----|-----------|
| **P1** | Onboard tag-blocked tenants to model-backend monitors | 16 tenants have no Bedrock/Azure monitoring; blocked on the `Environment=production` secret tag | v0.1.0 |
| ~~**P2**~~ | ~~Re-enable aigov Keycloak monitors and dashboard~~ | **Done** — aigov Keycloak monitors + dashboard now Terraform-managed (see Completed) | v0.1.0 |
| **P3** | Validate Bedrock anomaly monitor baseline | The new anomaly-based throughput-collapse monitor needs baseline warm-up confirmation across tenants | v0.1.0 |

## Milestones

### Milestone: v0.1.0 — Complete the multi-tenant monitor rollout

**Onboard tag-blocked tenants to model-backend monitors**
Extend the per-tenant rollout in `terraform/tenants.tf` to the 16 tenants whose
`*-shared-dd-*` secrets are not yet readable (tracked in
`terraform/tenants.pending.md`): aigov, ang, doc, doi, doli, dot, ed, fhfa, gsa,
gsai, hhs, hud, ncua, opm, pc, sss, stateoig, usda. Each needs
`Environment=production` (and `Tenant=usai-<slug>`) tags applied to its DD
secrets so the `Tenant_Aigov_Tech_Lead` role can `GetSecretValue` (the
`FCS_IDC_CMP_Tenant_TechLeads` policy gates on that tag). Once a tenant's secret
is readable, add its block to `tenants.tf` (aws provider alias, secret data
sources, datadog provider alias, module call). Note three non-standard secret
names: aigov uses `aigov-shared-dd-*`, doli uses `doli-shared-dd-*`, gsai uses
`gsai-shared-dd-*`. The disa account has no SSO access at all and is out of scope
until that is resolved.

**Re-enable aigov Keycloak monitors and dashboard** — ✅ **Done.**
The 5 aigov-specific Keycloak log alerts (`terraform/monitors.tf`) and the Keycloak
dashboard (`terraform/dashboard.tf`) are now Terraform-managed via the
`datadog.aigov` provider alias in `tenants.tf`. The pre-existing hand-created
resources were adopted with `terraform import` (monitors 568525–568532, dashboard
`g2g-uxq-vqh`) — no duplicates created. aigov gets only these Keycloak assets, not
the `model_backend_monitors` module. See the Completed section for the two
known-benign perpetual diffs (auto-attached runbook `assets`, dashboard
`notify_list`).

**Validate Bedrock anomaly monitor baseline**
The `bedrock_invocations_drop` monitor in
`terraform/modules/model_backend_monitors/main.tf` was converted from a static
threshold to a per-model anomaly alert (`agile`, 3 std devs, `direction=below`).
Anomaly monitors need baseline history to be reliable. Watch the 7 enabled orgs
over the next several days; if the agile/3-sigma tuning is too sensitive or too
loose on sparse models, adjust the bound or seasonality, or remove the monitor
(it overlaps the latency monitor).

## Completed

- **P2 — aigov Keycloak monitors + dashboard under Terraform.** Wired an
  `aws.aigov`/`datadog.aigov` provider pair in `tenants.tf` (no
  `model_backend_monitors` module — aigov is the shared account and gets only the
  Keycloak assets) and activated `monitors.tf` + `dashboard.tf` from the parked
  `.aigov-pending` files. Adopted the 5 pre-existing hand-created monitors
  (568525–568532) and the dashboard (`g2g-uxq-vqh`) via `terraform import` — no
  duplicates. Folded in the dashboard CPU/mem/pods tag fix
  (`app:keycloak` → `kube_deployment:keycloak`). Two known-benign perpetual diffs
  remain and represent no real drift: Datadog auto-attaches a "Datadog Runbook"
  `assets` block to each monitor after apply, and the dashboard API round-trips
  `notify_list = null`. The dashboard JSON carries no `tags` because the aigov org
  restricts dashboard tag keys to `team`/`ai`.
- Multi-tenant refactor: model-backend Bedrock + Azure OpenAI monitors rolled out
  to 7 enabled tenant orgs via a reusable module (PR #1).
- Remote S3 state backend in the shared `aigov-tenant-tfstate` bucket (PR #2).

## Future

- Per-tenant notification channel overrides (currently one shared Slack target).
- CI plan/apply with an OIDC-trusted role once secrets access is standardized.
