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
    Create the edge health/TLS/reachability synthetics (cert_monitors.tf).

    Default flipped false -> true on 2026-08-18. The previous default was false on
    the belief that public Datadog locations are blocked by the edge WAF's
    GSA/Zscaler allowlist, so a public-location test "would fail forever". That
    belief was DISPROVEN by live evidence: 16 hand-built synthetics have been
    running from the PUBLIC `aws:us-gov-west-1` location across these orgs since
    2026-04, and 15 of them sat in OK — they only broke when the tenant hostnames
    moved to the apex, not because of the WAF. See the corrected caveat in
    cert_monitors.tf. No private location is required.
  EOT
  type        = bool
  default     = true
}

variable "synthetic_locations" {
  description = <<-EOT
    Datadog Synthetics location ids to run the edge tests from. Defaults to the
    public GovCloud location `aws:us-gov-west-1`, which is verified to reach these
    endpoints (see enable_edge_synthetics). A private location id (pl:...) also
    works if one is ever provisioned. Empty disables synthetic creation regardless
    of enable_edge_synthetics.
  EOT
  type        = list(string)
  default     = ["aws:us-gov-west-1"]
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

variable "edge_domain_label" {
  description = <<-EOT
    DNS label under usai.gov for this tenant, when it differs from the tenant
    slug. Empty means "same as var.tenant".

    Exists because the slug and the DNS label are NOT always equal: tenant `doli`
    publishes at `chat.dol.usai.gov` (label `dol`), so a slug-derived host would
    silently monitor a name that does not resolve. Overriding the label fixes both
    the apex and console hosts at once; use var.edge_hosts instead if a tenant
    needs a wholly different host list.
  EOT
  type        = string
  default     = ""
}

variable "edge_hosts" {
  description = <<-EOT
    Override the public edge hostnames monitored for this tenant. Empty uses the
    label-derived default: <label>.usai.gov + console.<label>.usai.gov, where
    <label> is var.edge_domain_label (or var.tenant). Set explicitly for tenants
    whose edge naming differs beyond the label.

    NOTE the apex: as of the 2026-08 tenant rename the chat UI is served from the
    bare `<label>.usai.gov`, and `chat.<label>.usai.gov` 301-redirects to it. The
    old `chat.` default is gone — see the rename note in cert_monitors.tf.
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
