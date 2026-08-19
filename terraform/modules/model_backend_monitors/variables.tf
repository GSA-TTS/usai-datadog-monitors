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

    DEFAULT FALSE, and it must stay false — opt in PER TENANT in tenants.tf, only
    after verifying that tenant is reachable FROM THE DATADOG LOCATION.

    Reachability from `aws:us-gov-west-1` is a per-tenant property, not a global
    one. Measured 2026-08-18 across all 23: 15 tenants respond normally and 8
    (dnfsb, doj, faa, nrc, ntsb, oge, nsf, eeoc) TIME OUT — "The request couldn't
    be completed in a reasonable time", with no status code and no TLS error,
    which is the signature of a silent perimeter drop rather than an app fault.

    HOW TO VERIFY — do NOT use curl from a GSA laptop. A laptop on the GSA network
    or Zscaler is INSIDE the WAF allowlist, so it reaches every tenant and tells
    you nothing about Datadog's egress. This exact mistake shipped 56 alerting
    tests across the 8 unreachable orgs on 2026-08-18: all 46 hostnames were
    verified 200/valid-cert by laptop curl beforehand. Verify instead by creating
    ONE test for the tenant, letting it run, and reading the result from
    `/api/v1/synthetics/tests/<id>/results` — or by adding that tenant's edge to
    the WAF allowlist for the Datadog gov ranges.
  EOT
  type        = bool
  default     = false
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

variable "app_namespaces" {
  description = <<-EOT
    Kubernetes namespaces holding the USAI application, used to scope the
    deployment-availability monitor. An ALLOWLIST, deliberately — not a blocklist
    of platform namespaces.

    Why: the monitor was originally scoped `{*}`, so it watched every deployment in
    the cluster including platform add-ons. On 2026-07-22 a Calico upgrade added
    `goldmane` and `whisker` to `calico-system` on eeoc; both sat unready and the
    monitor paged every 2h for 28 days about components that are not USAI and not
    on-call's to fix (12 emails/day). A blocklist would have needed editing for
    each new add-on — i.e. it fails open, exactly the way this did. An allowlist
    fails closed: a new platform namespace is ignored by default.

    The trade-off is real: a NEW USAI namespace must be added here or it goes
    unmonitored. Verified 2026-08-19 against live kube-state-metrics — the app runs
    in these five, and the other nine namespaces in-cluster (amazon-cloudwatch,
    calico-system, cattle-fleet-system, cattle-system, flux-system, istio-system,
    kube-system, mcaas-backend, tigera-operator) are all platform.

    Note what is NOT lost by excluding istio-system/mcaas-backend: a broken
    istio-ingressgateway surfaces via the edge synthetics, and a broken
    datadog-cluster-agent via the agent-telemetry monitor.
  EOT
  type        = list(string)
  default     = ["core-api", "core-chat", "core-console", "chat-beta", "api-beta"]
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
