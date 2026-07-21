# Tenants pending enablement

Multi-tenant rollout of USAi monitors + dashboards.
A tenant becomes enable-able once its `*-shared-dd-api-key` / `*-shared-dd-app-key`
secrets are readable by the `Tenant_Aigov_Tech_Lead` SSO role — which requires
the secrets to carry the `Environment=production` tag (the
`FCS_IDC_CMP_Tenant_TechLeads` IAM policy only grants `secretsmanager:*` on
resources tagged `Environment in [prod, production]`).

## Enabled (23) — secrets readable, wired in `tenants.tf`

ang, dnfsb, doc, doi, doj, doli, dot, ed, faa, fhfa, ftc, gsa, hhs, hud,
ncua, nrc, ntsb, opm, oge, pc, sss, stateoig, usda

(Original 7 enabled 2026-06-10; remaining 16 unblocked 2026-07-09 after FCS
applied tagging to all USAi agencies.)

Note non-standard secret names / profiles:
- doli → `doli-shared-dd-api-key` / `doli-shared-dd-app-key`, profile `aigov-doli`
- Most new tenants → `usai-<tenant>-shared-dd-*` (not `<tenant>-shared-dd-*`)

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
