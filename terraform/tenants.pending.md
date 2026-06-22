# Tenants pending enablement

Multi-tenant rollout of the model-backend monitors (Bedrock + Azure OpenAI).
A tenant becomes enable-able once its `*-shared-dd-api-key` / `*-shared-dd-app-key`
secrets are readable by the `Tenant_Aigov_Tech_Lead` SSO role — which requires
the secrets to carry the `Environment=production` tag (the
`FCS_IDC_CMP_Tenant_TechLeads` IAM policy only grants `secretsmanager:*` on
resources tagged `Environment in [prod, production]`).

## Enabled (7) — secrets readable, wired in `tenants.tf`

dnfsb, doj, faa, ftc, nrc, ntsb, oge

(The `Environment=production` tag was applied to these 7 Phase-B accounts on
2026-06-10.)

## Blocked on tagging (16) — `GetSecretValue` returns AccessDenied

aigov, ang, doc, doi, doli (aigov-doli), dot, ed, fhfa, gsa, gsai, hhs, hud,
ncua, opm, pc, sss, stateoig, usda

Action: apply the same `Environment=production` (+ `Tenant=usai-<slug>`) tags to
the `*-shared-dd-*` secrets in each of these accounts, then add a tenant block to
`tenants.tf`. Note three non-standard secret names:
- aigov → `aigov-shared-dd-api-key` / `aigov-shared-dd-app-key`
- doli  → `doli-shared-dd-api-key`  / `doli-shared-dd-app-key`
- gsai  → `gsai-shared-dd-api-key`  / `gsai-shared-dd-app-key`

## No SSO access

disa — the `disa` SSO profile returns ForbiddenException on GetRoleCredentials
(no role access at all), separate from the tagging issue.

## aigov Keycloak monitors + dashboard

`monitors.tf.aigov-pending` and `dashboard.tf.aigov-pending` hold the 5
aigov-specific Keycloak log alerts and the Keycloak dashboard. They are
aigov-only (queries reference aigov clients; import IDs are aigov's) and are
disabled until aigov's secret is readable. See `providers.tf` for re-enable
steps.
