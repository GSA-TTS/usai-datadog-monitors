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

- Keycloak monitors (5 log alerts)
- Keycloak dashboard
- Bedrock monitors (4 metric alerts)
- Azure OpenAI monitors (2 log alerts)

The infra monitors (Daily Log Index Usage, EMERGENCY istio proxy) are managed by FCS and are **not** included.

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

## Terraform Usage

```bash
cd terraform

# Set credentials (from AWS Secrets Manager or Datadog Org Settings)
export TF_VAR_datadog_api_key="<32-char hex key from Org Settings → API Keys>"
export TF_VAR_datadog_app_key="<app key with monitors_write + dashboards_write scope>"

terraform init
terraform plan
terraform apply
```

### First Run — Import Existing Resources

The Keycloak monitors and dashboard were originally created manually via the Datadog UI.
Before the first `terraform apply`, import them so Terraform doesn't create duplicates:

```bash
terraform import datadog_monitor.keycloak_login_failures_spike 568525
terraform import datadog_monitor.keycloak_login_success_rate_drop 568526
terraform import datadog_monitor.keycloak_invalid_credentials_spike 568528
terraform import datadog_monitor.keycloak_active_users_drop 568529
terraform import datadog_monitor.keycloak_top_failing_clients_spike 568532
terraform import datadog_dashboard_json.keycloak g2g-uxq-vqh
```

After import, `terraform plan` will show any drift between the live state and the code.

### Required Permissions

The application key needs these scopes:
- `monitors_read` / `monitors_write`
- `dashboards_read` / `dashboards_write`

Or leave the key as "Not Scoped" to inherit all permissions from the user.
