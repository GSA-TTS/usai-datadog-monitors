# Inputs for the model-backend monitor module.
#
# This module is instantiated once per tenant org. The caller passes a
# tenant-specific `datadog` provider (authed with that org's keys) via the
# module's `providers` argument, plus the variables below.

variable "tenant" {
  description = "Tenant slug, e.g. \"doj\". Used in monitor names and tags so alerts are attributable per org."
  type        = string
}

variable "notification_channel" {
  description = "Notification target appended to each monitor message (Slack handle / @-mention)."
  type        = string
}

variable "dashboard_epoch" {
  description = <<-EOT
    Unix epoch (seconds) used as the "now" anchor for the istio root-cert
    days-remaining countdown widget. Datadog widget queries have no now()
    function, so the countdown subtracts this baked-in constant from the cert's
    absolute expiry timestamp. The displayed value therefore drifts slowly (it
    over-counts as wall-clock passes this anchor) — fine for a multi-year root
    cert. Re-stamp it to "now" on apply to refresh the baseline:
      terraform apply -var=dashboard_epoch=$(date +%s)
    The default is a fixed stamp so plans are deterministic (no perpetual diff
    from timestamp()).
  EOT
  type        = number
  default     = 1782234624 # 2026-06-23 — bump on apply to refresh the countdown
}
