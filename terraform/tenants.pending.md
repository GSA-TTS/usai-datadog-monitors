# Tenants pending enablement

Multi-tenant rollout of USAi monitors + dashboards.
A tenant becomes enable-able once its `*-shared-dd-api-key` / `*-shared-dd-app-key`
secrets are readable by the `Tenant_Aigov_Tech_Lead` SSO role — which requires
the secrets to carry the `Environment=production` tag (the
`FCS_IDC_CMP_Tenant_TechLeads` IAM policy only grants `secretsmanager:*` on
resources tagged `Environment in [prod, production]`).

## Enabled (12) — secrets readable, wired in `tenants.tf`

dnfsb, doc, doi, doj, dot, ed, fhfa, ftc, gsa, hud, ncua, nrc, ntsb, pc, sss, stateoig, usda

(Original 7 enabled 2026-06-10; remaining tenants unblocked 2026-07-09 after FCS
applied tagging to all USAi agencies. nsf + eeoc onboarded 2026-07-25 — PR #32.
Offboarding: ang, disa/jitc, eeoc, faa, frtib removed 2026-11-24; hhs, opm, oge removed 2026-11-24 — PR #XX.)

Note non-standard secret names / profiles:
- Most tenants → `usai-<tenant>-shared-dd-*` (not `<tenant>-shared-dd-*`)

## Offboarded (8) — secrets access lost, resources removed

ang, disa/jitc, eeoc, faa, frtib, hhs, opm, oge

These tenants were offboarded 2026-11-24. All provider aliases, data sources,
modules, and RUM credentials have been removed from `tenants.tf` and `outputs.tf`.
The faa and eeoc Keycloak realms were also removed from the `scim_realms` list in aigov
monitoring.

Terraform will destroy their live Datadog resources (monitors, synthetics,
dashboards, RUM apps) when applied.

## Removed from Terraform management — secret access lost (1)

doli

`doli` was removed from `tenants.tf` after the DevOps/SRE role lost
`secretsmanager:GetSecretValue` access to Datadog API/app-key secrets.
Terraform cannot configure that tenant's Datadog provider without the keys, so
it cannot destroy or update live Datadog resources. Remove existing
objects from Terraform state with `terraform state rm` (state-only) when applying
this change; any live Datadog resources in that org are then orphaned and must
be cleaned up manually if needed.

## No SSO access — disa

disa — the `disa` SSO profile returns ForbiddenException on GetRoleCredentials
(no role access at all), separate from the tagging issue.

## aigov Keycloak monitors + dashboard — managed

`terraform/monitors.tf` (5 aigov-specific Keycloak log alerts) and
`terraform/dashboard.tf` (the Keycloak dashboard) are now Terraform-managed via
the `datadog.aigov` provider alias. The pre-existing hand-created resources were
adopted via `terraform import` (monitors 568525–568532, dashboard `g2g-uxq-vqh`)
— no duplicates. ROADMAP P2, done.
