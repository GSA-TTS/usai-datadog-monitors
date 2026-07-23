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

- Bedrock monitors (3 metric alerts) — **rolled out per-tenant** to every enabled org
- Azure OpenAI monitors (2 log alerts) — **rolled out per-tenant** to every enabled org
- Model-backend dashboard (Bedrock + Azure OpenAI triage view) — **rolled out per-tenant** to every enabled org
- Infrastructure-health monitors (2 log alerts: istio mTLS cert-signing, dd-trace agent telemetry-send) — **rolled out per-tenant** to every enabled org
- App Health / Edge / Datadog-usage dashboards — **rolled out per-tenant** to every enabled org
- Keycloak monitors (5 log alerts) — **aigov-only**, managed by Terraform (see below)
- Keycloak dashboard — **aigov-only**, managed by Terraform (see below)

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
| `bedrock_invocation_latency_high` | avg latency per model (the incident's leading signal) | >60s over 15m |
| `bedrock_invocation_throttles` | AWS rate-limiting (quota hit) | >5 in 5m |
| `bedrock_server_errors` | 5xx from the model service | >5 in 5m |

> A `bedrock_invocations_drop` "throughput collapse" monitor was tried and removed
> (2026-06-23). Neither a static threshold nor a per-model anomaly alert worked
> across tenants with intermittent low-traffic models — it wedged in Alert on a
> model that stopped emitting and re-paged hourly. The latency monitor catches the
> same saturation failure upstream and is volume-independent.

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

The 5 aigov-specific Keycloak log alerts and the Keycloak dashboard are **managed
by Terraform** (`terraform/monitors.tf`, `terraform/dashboard.tf`), pointed at the
`datadog.aigov` provider alias. aigov is the shared account and gets *only* these
Keycloak assets — it does **not** get the per-tenant `model_backend_monitors`
module. They were adopted from the pre-existing hand-created resources via
`terraform import` (monitors 568525–568532, dashboard `g2g-uxq-vqh`), so no
duplicates were created.

Two **known-benign perpetual diffs** show up on every `plan` and can be applied or
ignored (they never converge and represent no real drift):
- Each monitor shows a `- assets { ... "Datadog Runbook" ... }` removal — Datadog
  auto-attaches a runbook notebook link to every monitor after apply.
- The dashboard shows `- notify_list = null` — an API round-trip artifact.

The dashboard JSON carries **no `tags`** — the aigov org restricts dashboard-level
tag keys to `team`/`ai` and rejects `managed-by:terraform`/`service:keycloak`
(those tags live on the monitors instead, which have no such restriction).

### Required Permissions

- AWS: `secretsmanager:GetSecretValue` on each tenant's `usai-<tenant>-shared-dd-*`
  secrets (granted via the `Environment=production` tag).
- Datadog app key scopes: `monitors_read` / `monitors_write` (and
  `dashboards_read` / `dashboards_write` for the aigov dashboard).
