# ---------------------------------------------------------------------------
# Edge TLS / reachability monitoring (Synthetics) — added after the 2026-08-04
# EEOC onboarding incident: the beta-stack rollout generated the beta cert
# (api.beta.<tenant>...) but NOT the production certs for chat.<tenant>.usai.gov
# / console.<tenant>.usai.gov, so client TLS failed with a wrong/missing-cert
# error and nobody was alerted. These catch that class of failure proactively:
#
#   1. ssl_cert_<host>  — SSL synthetic: cert present, chain valid, hostname/SAN
#                         match, AND more than cert_expiry_crit_days (14) to
#                         expiry. Fires on missing / wrong / untrusted /
#                         expiring cert (the exact EEOC failure).
#   2. https_reach_<host> — HTTP synthetic: GET returns 200/302 over valid TLS.
#                         Catches the cert error indirectly PLUS the network/
#                         allowlist drop the EEOC client also hit.
#   3. cert_expiry_<host> — metric-style alert on the SSL test's days-remaining,
#                         so an expiring (not-yet-broken) cert warns early.
#
# ── LOAD-BEARING CAVEAT: WAF ALLOWLIST vs SYNTHETIC SOURCE IPs ──────────────
# These endpoints sit behind a WAF whose default action is BLOCK with an
# allowlist of GSA on-prem + Zscaler ranges (see the EEOC incident: that
# allowlist is exactly what the client tripped). Datadog **managed/public**
# synthetic locations egress from public Datadog IPs that are NOT in that
# allowlist, so a public-location test would be BLOCKED by the WAF and fail
# forever — false alerts, not real monitoring.
#
# Therefore `synthetic_locations` defaults to a PRIVATE LOCATION id that must
# be provisioned inside the tenant network (or its allowlisted egress) and its
# IP/range added to the WAF allowlist. Until that private location exists,
# leave `enable_edge_synthetics = false` (the default) so no test is created.
# Do NOT switch to a public `aws:us-east-1` location expecting it to work —
# it will be silently blocked. (Same "looks-right-but-doesn't-apply" class as
# the aigov dashboard-tag gotcha.)
# ---------------------------------------------------------------------------

locals {
  # Public edge hostnames per tenant. Default derives from the slug
  # (chat.<tenant>.usai.gov / console.<tenant>.usai.gov); override via
  # var.edge_hosts for tenants whose naming differs (e.g. doli).
  edge_hosts = length(var.edge_hosts) > 0 ? var.edge_hosts : [
    "chat.${var.tenant}.usai.gov",
    "console.${var.tenant}.usai.gov",
  ]

  # Only create synthetics when explicitly enabled AND a private location is set
  # (public locations are blocked by the WAF — see the caveat above).
  edge_synthetics_enabled = var.enable_edge_synthetics && length(var.synthetic_locations) > 0

  edge_hosts_effective = local.edge_synthetics_enabled ? local.edge_hosts : []

  cert_expiry_warn_days = 45 # warn early — cert generation takes ~15m + a PR
  cert_expiry_crit_days = 14 # crit — genuinely close, page it
}

# --- 1. SSL cert validity + expiry (the direct EEOC fix) --------------------
resource "datadog_synthetics_test" "ssl_cert" {
  for_each = toset(local.edge_hosts_effective)

  name      = "[${var.tenant}] Edge TLS cert invalid/missing — ${each.value}"
  type      = "api"
  subtype   = "ssl"
  status    = "live"
  locations = var.synthetic_locations
  message   = <<-EOT
    {{#is_alert}}
    TLS certificate check FAILED for https://${each.value} (${var.tenant}): the served certificate is missing, does not match the hostname, is untrusted, or is expiring. This is the failure mode of the 2026-08-04 EEOC incident (prod cert not generated during a beta-stack rollout). Verify the ACM cert covering ${each.value} exists and is attached to the load balancer.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: TLS certificate for ${each.value} is valid again.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Edge host: ${each.value}
  EOT

  request_definition {
    host = each.value
    port = "443"
  }

  # Cert must be valid (chain + hostname/SAN match) AND have more than
  # cert_expiry_crit_days left. For subtype=ssl, the `certificate` assertion's
  # target is the days-remaining threshold; isInMoreThan asserts days_left >
  # target. An invalid/missing/mismatched cert fails the check outright.
  assertion {
    type     = "certificate"
    operator = "isInMoreThan"
    target   = local.cert_expiry_crit_days
  }

  options_list {
    tick_every           = 300 # every 5m
    accept_self_signed   = false
    min_failure_duration = 300
    min_location_failed  = 1
    retry {
      count    = 2
      interval = 30000
    }
  }

  tags = concat(local.base_tags, ["service:edge-tls", "check:ssl-cert"])
}

# --- 2. HTTPS reachability (catches TLS fail + network/allowlist drop) ------
resource "datadog_synthetics_test" "https_reach" {
  for_each = toset(local.edge_hosts_effective)

  name      = "[${var.tenant}] Edge unreachable / bad status — ${each.value}"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = var.synthetic_locations
  message   = <<-EOT
    {{#is_alert}}
    https://${each.value} (${var.tenant}) is not returning a healthy status. Either TLS is failing (bad/missing cert), the app has no ready backend, or traffic is being dropped upstream (WAF/network allowlist). Cross-check the edge dashboard and the deployment-availability monitor.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: https://${each.value} responding normally.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Edge host: ${each.value}
  EOT

  request_definition {
    method = "GET"
    url    = "https://${each.value}/"
  }

  # statusCode only supports is/isNot operators. Follow redirects so chat's
  # 302 -> /auth/login -> Keycloak resolves to a final 200 (console is 200
  # directly). This also exercises the full TLS chain incl. auth.usai.gov. A
  # missing/bad cert or upstream drop fails the request before any assertion.
  assertion {
    type     = "statusCode"
    operator = "is"
    target   = 200
  }

  options_list {
    tick_every           = 300
    follow_redirects     = true
    min_failure_duration = 300
    min_location_failed  = 1
    retry {
      count    = 2
      interval = 30000
    }
  }

  tags = concat(local.base_tags, ["service:edge-tls", "check:https-reach"])
}

# --- 3. Cert-expiry early-warning (metric monitor on the SSL test) ----------
# The SSL synthetic above CRITs at <14 days. This monitor warns earlier (45d)
# off the same synthetic's days-remaining metric, so a slowly-expiring cert is
# caught with time to rotate rather than only when it breaks.
resource "datadog_monitor" "cert_expiry" {
  for_each = toset(local.edge_hosts_effective)

  name = "[${var.tenant}] Edge TLS cert expiring soon — ${each.value}"
  type = "metric alert"

  # Datadog requires the query threshold to equal the CRITICAL threshold; the
  # warning (larger, since fewer-days-left counts down) trips first via
  # monitor_thresholds.warning. So the query uses cert_expiry_crit_days.
  query = "min(last_5m):min:synthetics.ssl.days_left{check_id:${datadog_synthetics_test.ssl_cert[each.value].id}} < ${local.cert_expiry_crit_days}"

  message = <<-EOT
    {{#is_warning}}
    TLS certificate for ${each.value} (${var.tenant}) expires in fewer than ${local.cert_expiry_warn_days} days. Rotate/renew via ACM before it breaks client access. (Cert generation + PR takes time — do not wait for the hard failure.)
    {{/is_warning}}
    {{#is_alert}}
    TLS certificate for ${each.value} (${var.tenant}) expires in fewer than ${local.cert_expiry_crit_days} days — imminent. Renew now.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: cert for ${each.value} renewed / days-remaining back above threshold.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Edge host: ${each.value}
  EOT

  # The 45d warn tier is deliberately handle-less (no notification_channel in the
  # {{#is_warning}} block): a cert 45 days out is a ticket, not a page. Per repo
  # convention the recovery block must then be {{#is_alert_recovery}}, NOT bare
  # {{#is_recovery}} — the latter also fires on WARN->OK and would ping the
  # channel for a warn tier that never paged (the PR #22/#28 noise class).
  monitor_thresholds {
    warning  = local.cert_expiry_warn_days
    critical = local.cert_expiry_crit_days
  }

  notify_no_data    = false
  renotify_interval = 0
  tags              = concat(local.base_tags, ["service:edge-tls", "check:cert-expiry"])
}

# ---------------------------------------------------------------------------
# ACM cert-expiry (metric monitor via the AWS integration)
# ---------------------------------------------------------------------------
# ⚠️ UNVERIFIED — DO NOT ENABLE WITHOUT RE-TESTING (2026-08-04). In a live
# test on gsa this monitor read "No Data" persistently for ~6 minutes even
# though the underlying metric `aws.certificatemanager.days_to_expiry` returned
# real series via the query API (two certs: 65 and 170 days). Root cause not
# resolved — likely freshly-created-monitor eval latency on a sparse metric
# (ACM publishes ~1 point/hour, observed ~17m stale) OR a monitor-eval vs
# query-API namespace nuance. Widening the window (1h→4h) and no_data_timeframe
# (2h→24h) did not clear it within the test window. It was applied then
# DESTROYED during testing — it has never successfully evaluated.
#
# BEFORE enabling (var.enable_acm_cert_monitor): apply to ONE working tenant
# (gsa/doc — confirmed to emit the metric), then WATCH for 15-20 min. It must
# reach `OK` (evaluating with data), not stay `No Data`. If it stays No Data,
# do NOT roll out — notify_no_data=true would false-page every tenant. The
# metric IS present (query API proves it), so this is a monitor-config problem
# to solve, not a missing-metric one. See RETRO / the EEOC-cert thread.
#
# Gated behind its OWN flag (var.enable_acm_cert_monitor, default false) —
# separate from the synthetics' enable_edge_synthetics so neither can turn the
# other on by accident.
#
# Design intent (once it works): unlike the synthetics above (blocked by the
# WAF from public locations, so gated until a private location exists), this
# uses the CloudWatch `aws.certificatemanager.days_to_expiry` metric the Datadog
# AWS integration already collects — series confirmed present on gsa/doc — so it
# would evaluate with no private location and no WAF dependency.
#
# SCOPE / GRANULARITY CAVEAT: the CloudWatch stream here emits this metric
# WITHOUT per-cert dimensions (certificate_arn/domainname tag = "N/A"), so the
# value is the account-level aggregate — effectively "days until the
# soonest-expiring ACM cert in this tenant account". That's the right signal
# for "a prod cert is about to lapse" (the EEOC-adjacent failure), but it
# CANNOT attribute which specific cert, and it does NOT catch a *missing* cert
# (a cert that was never created emits no metric — that's the synthetic's job).
# Treat this as the cheap always-on expiry backstop; the SSL synthetic is the
# missing/wrong-cert detector once a private location is provisioned.
#
# NO-DATA IS MEANINGFUL HERE: a tenant whose AWS integration isn't wired yet
# (e.g. eeoc at creation — Bedrock/ALB/ACM all returned 0 series) emits nothing.
# notify_no_data=true so "we can't even see this tenant's certs" pages rather
# than failing silent (the silent-monitor trap called out in infra_monitors.tf).
resource "datadog_monitor" "acm_cert_expiry" {
  # UNVERIFIED (see header) — gated off by its own flag; creates nothing until
  # someone re-tests the No-Data behavior and explicitly enables it.
  count = var.enable_acm_cert_monitor ? 1 : 0

  name = "[${var.tenant}] ACM cert expiring soon (account soonest-expiry)"
  type = "metric alert"

  # ACM publishes days_to_expiry to CloudWatch SPARSELY (~1 point/hour, and
  # observed up to ~17m stale). A last_1h window falls into the gaps between
  # points and flaps to No-Data. last_4h always spans several points so the
  # monitor evaluates continuously; days_to_expiry changes by 1/day so a 4h
  # aggregation window costs no precision. (Verified: last_1h → No Data on gsa
  # despite a live 170-day series; widening fixes it.)
  query = "min(last_4h):min:aws.certificatemanager.days_to_expiry{*} < ${local.cert_expiry_crit_days}"

  message = <<-EOT
    {{#is_warning}}
    An ACM certificate in the ${var.tenant} account expires in fewer than ${local.cert_expiry_warn_days} days (soonest-expiring cert, account-level metric — this monitor can't name the specific cert). Identify and renew it in ACM before it breaks client TLS. Prod cert lapses are the EEOC-incident failure class.
    {{/is_warning}}
    {{#is_alert}}
    An ACM certificate in the ${var.tenant} account expires in fewer than ${local.cert_expiry_crit_days} days — imminent. Renew now.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_no_data}}
    No ACM cert-expiry metric from the ${var.tenant} account for 24h. The Datadog AWS integration may not be wired for this (sub-)account — cert expiry is currently UNMONITORED here. Confirm the CloudWatch metric stream / integration is enabled.
    ${var.notification_channel}
    {{/is_no_data}}
    {{#is_alert_recovery}}
    Recovered: soonest ACM cert expiry back above threshold for ${var.tenant}.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Metric: aws.certificatemanager.days_to_expiry (account aggregate)
  EOT

  # 45d warn tier is handle-less (ticket, not a page), so the recovery block uses
  # {{#is_alert_recovery}} rather than bare {{#is_recovery}} — see the same note
  # on cert_expiry above.
  monitor_thresholds {
    warning  = local.cert_expiry_warn_days
    critical = local.cert_expiry_crit_days
  }

  notify_no_data    = true
  no_data_timeframe = 1440 # 24h — ACM metric is ~hourly+sparse; only a genuine
  # integration outage (not a scrape gap) should trip no-data. 2h would false-page.
  renotify_interval = 0
  tags              = concat(local.base_tags, ["service:edge-tls", "check:acm-cert-expiry"])
}
