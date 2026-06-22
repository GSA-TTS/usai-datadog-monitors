variable "notification_channel" {
  description = "Default Slack notification target for monitor alerts (tenant orgs without an explicit override)."
  type        = string
  default     = "@tenant-operations-aaaas4jm3nfumzk46ws4bhiu7i@gsa.org.slack.com"
}

# Keys are sourced per-tenant from AWS Secrets Manager (see providers.tf /
# tenants.tf), not from TF_VAR_* — so no datadog_api_key/datadog_app_key
# variables here. Each tenant's keys live in its own AWS account under the
# secret names declared in the `tenants` local (tenants.tf).
