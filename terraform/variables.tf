variable "datadog_api_key" {
  description = "Datadog API key for the aigov org"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog Application key with monitors_write and dashboards_write scopes"
  type        = string
  sensitive   = true
}

variable "notification_channel" {
  description = "Slack notification target for monitor alerts"
  type        = string
  default     = "@tenant-operations-aaaas4jm3nfumzk46ws4bhiu7i@gsa.org.slack.com"
}
