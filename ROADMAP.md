# usai-datadog-monitors ROADMAP

## Priority Matrix

| Priority | Feature | Why | Milestone |
|----------|---------|-----|-----------|
| **P1** | Onboard tag-blocked tenants to model-backend monitors | 16 tenants have no Bedrock/Azure monitoring; blocked on the `Environment=production` secret tag | v0.1.0 |
| **P2** | Re-enable aigov Keycloak monitors and dashboard | aigov-specific Keycloak alerts + dashboard are parked, leaving aigov auth unmonitored | v0.1.0 |
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

**Re-enable aigov Keycloak monitors and dashboard**
The 5 aigov-specific Keycloak log alerts and the Keycloak dashboard are parked as
`terraform/monitors.tf.aigov-pending` and `terraform/dashboard.tf.aigov-pending`.
Re-enable once aigov's secret is readable: rename to `.tf`, add an aigov block to
`tenants.tf`, point the resources at `provider = datadog.aigov`, and import the
existing live resources (IDs in `README.md`) so Terraform adopts rather than
duplicates them. Steps are documented in `terraform/providers.tf`.

**Validate Bedrock anomaly monitor baseline**
The `bedrock_invocations_drop` monitor in
`terraform/modules/model_backend_monitors/main.tf` was converted from a static
threshold to a per-model anomaly alert (`agile`, 3 std devs, `direction=below`).
Anomaly monitors need baseline history to be reliable. Watch the 7 enabled orgs
over the next several days; if the agile/3-sigma tuning is too sensitive or too
loose on sparse models, adjust the bound or seasonality, or remove the monitor
(it overlaps the latency monitor).

## Completed

- Multi-tenant refactor: model-backend Bedrock + Azure OpenAI monitors rolled out
  to 7 enabled tenant orgs via a reusable module (PR #1).
- Remote S3 state backend in the shared `aigov-tenant-tfstate` bucket (PR #2).

## Future

- Per-tenant notification channel overrides (currently one shared Slack target).
- CI plan/apply with an OIDC-trusted role once secrets access is standardized.
