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

The infra monitors (Daily Log Index Usage, EMERGENCY istio proxy) are managed by FCS and are **not** included.

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
