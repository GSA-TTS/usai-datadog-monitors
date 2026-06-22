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
