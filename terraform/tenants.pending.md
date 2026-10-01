# Tenants pending enablement

Multi-tenant rollout of USAi monitors + dashboards.
A tenant becomes enable-able once its `*-shared-dd-api-key` / `*-shared-dd-app-key`
secrets are readable by the `Tenant_Aigov_Tech_Lead` SSO role — which requires
the secrets to carry the `Environment=production` tag (the
`FCS_IDC_CMP_Tenant_TechLeads` IAM policy only grants `secretsmanager:*` on
resources tagged `Environment in [prod, production]`).

## Enabled (23) — secrets readable, wired in `tenants.tf`

dnfsb, doc, doi, doj, dot, ed, eeoc, faa, fhfa, ftc, gsa, hhs, hud, ncua,
nrc, nsf, ntsb, opm, oge, pc, sss, stateoig, usda

(Original 7 enabled 2026-06-10; remaining 16 unblocked 2026-07-09 after FCS
applied tagging to all USAi agencies. nsf + eeoc onboarded 2026-07-25 — PR #32;
this list had not been updated for them, corrected here.)

Note non-standard secret names / profiles:
- Most new tenants → `usai-<tenant>-shared-dd-*` (not `<tenant>-shared-dd-*`)

## Alerting retired (3) — RUM and dashboards retained

oge, hhs, opm

These tenants stay wired in `tenants.tf`, but set `enable_alerting = false`.
Terraform destroys their per-tenant monitors and synthetics while keeping their
RUM applications and dashboards, so residual traffic remains visible.

Root-module aigov SCIM monitoring still includes the `opm` realm because it
targets shared Keycloak, not the opm Datadog org.

## Removed from Terraform management — secret access lost (2)

ang, doli

`ang` and `doli` were removed from `tenants.tf` after the DevOps/SRE role lost
`secretsmanager:GetSecretValue` access to their Datadog API/app-key secrets.
Terraform cannot configure those tenants' Datadog providers without the keys, so
it cannot destroy or update their live Datadog resources. Remove their existing
objects from Terraform state with `terraform state rm` (state-only) when applying
this change; any live Datadog resources in those orgs are then orphaned and must
be cleaned up manually if needed.

## aigov — wired (no model_backend module)

aigov is the shared account and does NOT get the standard per-tenant
`model_backend_monitors` module. It IS wired in `tenants.tf` (aws.aigov +
datadog.aigov provider aliases) for its Keycloak-only assets — see below.

## Blocked — gsai (KMS)

gsai secrets are listable but `GetSecretValue` returns
`AccessDeniedException: Access to KMS is not allowed`. The secret exists
(`gsai-shared-dd-api-key` / `gsai-shared-dd-app-key`) but the KMS key policy
doesn't grant decrypt to our role.

## No SSO access — disa

disa — the `disa` SSO profile returns ForbiddenException on GetRoleCredentials
(no role access at all), separate from the tagging issue.

## aigov Keycloak monitors + dashboard — managed

`terraform/monitors.tf` (5 aigov-specific Keycloak log alerts) and
`terraform/dashboard.tf` (the Keycloak dashboard) are now Terraform-managed via
the `datadog.aigov` provider alias. The pre-existing hand-created resources were
adopted via `terraform import` (monitors 568525–568532, dashboard `g2g-uxq-vqh`)
— no duplicates. ROADMAP P2, done.
