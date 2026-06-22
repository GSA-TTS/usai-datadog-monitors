# usai-datadog-monitors

Datadog monitor and dashboard configurations for the USAi platform, managed with Terraform.

## Structure

```
monitors/           # Raw JSON exports from Datadog API
  aigov/
  gsai/
dashboards/         # Raw JSON dashboard exports
  aigov/
terraform/          # Terraform IaC to create/update monitors and dashboards
```

## Orgs

| Org | Site | URL |
|-----|------|-----|
| aigov | ddog-gov.com | https://fcs-mcaas-aigov.ddog-gov.com |
| gsai | ddog-gov.com | https://fcs-mcaas-gsai.ddog-gov.com |

## What's Managed Here

Only resources **not** already managed by FCS Terraform (tagged `MCaaS - Managed by Terraform`):

- Bedrock monitors (4 metric alerts) — **rolled out per-tenant** to every enabled org
- Azure OpenAI monitors (2 log alerts) — **rolled out per-tenant** to every enabled org
- Model-backend dashboard (Bedrock + Azure OpenAI triage view) — **rolled out per-tenant** to every enabled org
- Keycloak monitors (5 log alerts) — **aigov-only**, currently parked (see below)
- Keycloak dashboard — **aigov-only**, currently parked (see below)

The infra monitors (Daily Log Index Usage, EMERGENCY istio proxy), the per-tenant
Synthetics checks, and the generic API latency/error-rate alerts already present in
some orgs are **not** managed here and are left untouched.

### Bedrock monitors (`bedrock_monitors.tf`)

Metric alerts on the `aws.bedrock.*` namespace (Datadog AWS integration), grouped
by `modelid`. Added after the 2026-06-02 GSA incident, where model invocation
latency (claude-sonnet-4-5, claude-opus-4-5) spiked from ~8s to 88–115s and
throughput collapsed — with **zero** AWS throttles/errors. Lesson: latency is the
leading indicator, not throttling.

| Monitor | Signal | Critical |
|---------|--------|----------|
| `bedrock_invocation_latency_high` | avg latency per model (the incident's leading signal) | >30s over 10m |
| `bedrock_invocation_throttles` | AWS rate-limiting (quota hit) | >5 in 5m |
| `bedrock_server_errors` | 5xx from the model service | >5 in 5m |
| `bedrock_invocations_drop` | throughput collapse (downstream symptom) | <3 over 15m |

### Azure OpenAI monitors (`azure_monitors.tf`)

Log alerts on the `api` service. The 2026-06-02 incident had a **second, concurrent**
failure mode the Bedrock metrics couldn't see: Azure OpenAI (GPT models) returned
HTTP 429 "Too Many Requests" and chat streams were aborted mid-flight. 19 such
events fired 15:38–18:43 EDT, peaking 16:11–16:30. This signal lives only in the
app logs, which is why the AWS-side and Azure-side failures were hard to correlate.

| Monitor | Signal | Critical |
|---------|--------|----------|
| `azure_openai_throttling` | `"Too Many Requests"` (429) from api service | >3 in 5m |
| `azure_openai_stream_aborted` | `"Stream aborted mid-flight"` (user-visible symptom) | >3 in 5m |

## Multi-Tenant Layout

The model-backend monitors (Bedrock + Azure OpenAI) are rolled out to **every USAi
tenant org**, each of which is a separate Datadog org under `ddog-gov.com`.

- `modules/model_backend_monitors/` — the 6 model-backend monitors, parameterized
  by tenant (names prefixed `[tenant]`, tagged `tenant:<slug>`).
- `tenants.tf` — one block per tenant: an `aws` provider alias (the tenant's SSO
  profile) → Secrets Manager data sources for that org's DD api/app keys → a
  `datadog` provider alias → a module call. Providers can't use `for_each`, so each
  tenant is an explicit block.
- `tenants.pending.md` — which tenants are enabled vs. blocked (and why).

Keys are read **directly from AWS Secrets Manager at plan time** (secret
`usai-<tenant>-shared-dd-{api,app}-key` in each tenant account) — there are no
`TF_VAR_datadog_*` variables. This requires the matching AWS SSO profiles to be
logged in, and the secrets to carry the `Environment=production` tag so the
`Tenant_Aigov_Tech_Lead` role can read them.

## Terraform Usage

```bash
cd terraform

# Log in to the AWS SSO profiles for the enabled tenants (keys are pulled from
# each account's Secrets Manager automatically — no env vars needed).
aws sso login --profile dnfsb   # etc. for each enabled tenant

terraform init
terraform plan
terraform apply
```

### aigov Keycloak monitors + dashboard

The 5 aigov-specific Keycloak log alerts and the Keycloak dashboard live in
`monitors.tf.aigov-pending` and `dashboard.tf.aigov-pending` (disabled — the
`.aigov-pending` suffix means Terraform ignores them). They are aigov-only and are
parked until aigov's secret is readable. See `providers.tf` for re-enable steps,
including importing the existing resources so Terraform adopts rather than
duplicates them:

```bash
terraform import datadog_monitor.keycloak_login_failures_spike 568525
terraform import datadog_monitor.keycloak_login_success_rate_drop 568526
terraform import datadog_monitor.keycloak_invalid_credentials_spike 568528
terraform import datadog_monitor.keycloak_active_users_drop 568529
terraform import datadog_monitor.keycloak_top_failing_clients_spike 568532
terraform import datadog_dashboard_json.keycloak g2g-uxq-vqh
```

### Required Permissions

- AWS: `secretsmanager:GetSecretValue` on each tenant's `usai-<tenant>-shared-dd-*`
  secrets (granted via the `Environment=production` tag).
- Datadog app key scopes: `monitors_read` / `monitors_write` (and
  `dashboards_read` / `dashboards_write` for the aigov dashboard).
