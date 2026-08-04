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

variable "enable_edge_synthetics" {
  description = <<-EOT
    Create the edge TLS/reachability synthetics (cert_monitors.tf). Default false
    because the tests are useless until a Datadog PRIVATE LOCATION exists inside
    the tenant's allowlisted egress — public Datadog synthetic IPs are blocked by
    the edge WAF's GSA/Zscaler allowlist and would fail forever. Set true (and
    provide synthetic_locations) once a private location is provisioned and its
    egress is added to the WAF allowlist.
  EOT
  type        = bool
  default     = false
}

variable "synthetic_locations" {
  description = <<-EOT
    Datadog Synthetics location ids to run the edge tests from. Must be a
    PRIVATE LOCATION id (pl:...) whose egress is in the edge WAF allowlist — NOT
    a public location like aws:us-east-1 (blocked by the WAF). Empty disables
    synthetic creation regardless of enable_edge_synthetics.
  EOT
  type        = list(string)
  default     = []
}

variable "enable_acm_cert_monitor" {
  description = <<-EOT
    Create the ACM cert-expiry metric monitor (cert_monitors.tf). Default false
    and UNVERIFIED: in testing it stayed "No Data" for ~6 min despite the metric
    being live via the query API — root cause unresolved. Before enabling, apply
    to one working tenant (gsa/doc) and watch 15-20 min that it reaches OK, not
    No Data (notify_no_data=true would false-page otherwise). See the resource
    header in cert_monitors.tf.
  EOT
  type        = bool
  default     = false
}

variable "edge_hosts" {
  description = <<-EOT
    Override the public edge hostnames monitored for this tenant. Empty uses the
    slug-derived default: chat.<tenant>.usai.gov + console.<tenant>.usai.gov.
    Set explicitly for tenants whose edge naming differs.
  EOT
  type        = list(string)
  default     = []
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
