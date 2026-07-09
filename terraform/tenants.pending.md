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

## Excluded — aigov

aigov is excluded from the standard per-tenant module (shared account, separate
treatment). Its secrets are readable but it is not wired in `tenants.tf`.

## Blocked — gsai (KMS)

gsai secrets are listable but `GetSecretValue` returns
`AccessDeniedException: Access to KMS is not allowed`. The secret exists
(`gsai-shared-dd-api-key` / `gsai-shared-dd-app-key`) but the KMS key policy
doesn't grant decrypt to our role.

## No SSO access — disa

disa — the `disa` SSO profile returns ForbiddenException on GetRoleCredentials
(no role access at all), separate from the tagging issue.

## aigov Keycloak monitors + dashboard

`monitors.tf.aigov-pending` and `dashboard.tf.aigov-pending` hold the 5
aigov-specific Keycloak log alerts and the Keycloak dashboard. They are
aigov-only (queries reference aigov clients; import IDs are aigov's) and are
disabled until aigov is onboarded separately. See `providers.tf` for re-enable
steps.
