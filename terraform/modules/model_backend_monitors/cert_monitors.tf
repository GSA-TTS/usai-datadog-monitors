# ---------------------------------------------------------------------------
# Edge health / TLS / reachability monitoring (Synthetics) — added after the
# 2026-08-04 EEOC onboarding incident: the beta-stack rollout generated the beta
# cert (api.beta.<tenant>...) but NOT the production certs for the tenant's public
# hosts, so client TLS failed with a wrong/missing-cert error and nobody was
# alerted. These catch that class of failure proactively:
#
#   0. edge_health_<apex> — HTTP synthetic on <label>.usai.gov/healthz asserting
#                         200 AND a "healthy" status body. This is the app-liveness
#                         check, and the Terraform-managed replacement for the
#                         hand-built UI tests that broke in the 2026-08 rename
#                         (see the rename section below). It is apex-only —
#                         /healthz is not a valid path on console or api.
#   1. ssl_cert_<host>  — SSL synthetic: cert present, chain trusted, not
#                         self-signed, AND more than cert_expiry_crit_days (14)
#                         to expiry. Datadog's documented SSL failure codes cover
#                         expired / untrusted / self-signed / revoked; SAN-
#                         hostname verification is NOT documented, so the
#                         wrong-hostname case is covered by check 2 rather than
#                         claimed here.
#   2. https_reach_<host> — HTTP synthetic: GET follows redirects and asserts a
#                         final 200 over valid TLS. Catches the cert error
#                         indirectly PLUS the network/allowlist drop the EEOC
#                         client also hit. This is also what actually covers the
#                         hostname/SAN-MISMATCH case: an HTTP client rejects a
#                         name-mismatched cert, whereas Datadog's SSL-test docs
#                         confirm expiry/trust/self-signed failures but do not
#                         document SAN verification.
#   3. ssl_cert_expiring_soon_<host> — the same SSL assertion at 45 days, so an
#                         expiring (not-yet-broken) cert warns early. Handle-less
#                         (a ticket, not a page).
#
# ── THE WAF CAVEAT IS PER-TENANT, NOT GLOBAL (settled 2026-08-18) ───────────
# This header long carried a "LOAD-BEARING CAVEAT": public Datadog locations are
# blocked by the edge WAF (default BLOCK + a GSA on-prem/Zscaler allowlist), so
# `enable_edge_synthetics` had to stay false pending a private location. It was
# then retracted wholesale on the strength of 16 hand-built UI synthetics that had
# been running from the PUBLIC `aws:us-gov-west-1` location since 2026-04 with 15
# in OK. Both positions were wrong, in opposite directions. The measured truth:
#
#   REACHABILITY FROM aws:us-gov-west-1 IS PER-TENANT.
#     reachable (15): doc doi dot ed fhfa ftc gsa hhs hud ncua opm pc sss
#                     stateoig usda
#     TIMES OUT  (8): dnfsb doj faa nrc ntsb oge nsf eeoc
#
# The 8 fail with "The request couldn't be completed in a reasonable time" — no
# status code, no TLS error — on the apex AND console, for health, cert and reach
# alike. That uniformity, plus the absence of any HTTP response, is a silent
# perimeter drop, not an app fault (their certs and endpoints are fine when probed
# from inside the allowlist).
#
# WHY THE RETRACTION WAS WRONG: the 16 passing tests only ever proved reachability
# for the hosts they targeted — 14 tenants' chat hosts. They said nothing about the
# 8 tenants that had never had a test, nor about console.*. Generalizing from the
# passing sample to all 23 tenants was the same unexamined leap as the original
# caveat, inverted. It shipped 56 alerting tests across 8 orgs before it was caught.
#
# THE LAPTOP TRAP — the reason it got past pre-apply verification: all 46 hostnames
# were probed with curl and returned 200 with valid certs. But a GSA laptop is on
# the network that IS in the WAF allowlist, so it reaches every tenant regardless.
# Laptop curl CANNOT falsify this failure mode. Verify from the Datadog location
# (create one test, read /api/v1/synthetics/tests/<id>/results) or not at all.
#
# So `enable_edge_synthetics` is back to default FALSE and is opted into per tenant
# in tenants.tf for the 15 verified-reachable orgs. `synthetic_locations` keeps its
# `["aws:us-gov-west-1"]` default because that location demonstrably works for
# those 15; a private location would be the way to cover the other 8.
#
# ── THE 2026-08 TENANT RENAME (why the UI tests broke) ──────────────────────
# Tenants moved from `chat.<label>.usai.gov` to the bare apex `<label>.usai.gov`,
# and it is a THREE-part change — each part alone breaks a naive health check:
#
#   1. host:  chat.<label>.usai.gov now 301-redirects to <label>.usai.gov.
#             Tests without follow_redirects fail `statusCode is 200` on the 301.
#   2. path:  /health is gone. On the apex it returns 404 with the SPA's HTML, so
#             following the redirect does NOT rescue a /health test. It is /healthz.
#   3. body:  the old payload was {"status":true}; the apex returns
#             {"status":"healthy","timestamp":...,"checks":{...}}. A
#             `$.status contains true` assertion fails against "healthy".
#
# Verified 2026-08-18: `https://<label>.usai.gov/healthz` returns 200 with
# {"status":"healthy"} on all 23 reachable tenants — including tenants whose
# `chat.` host had not yet been cut over. The apex is therefore safe to target
# uniformly and needs no per-tenant migration flag.
#
# Known non-conforming tenants (both real, neither a rename artifact):
#   - ang:  ang.usai.gov/healthz returns a genuine 503 and chat./console.ang do
#           not connect. Its test SHOULD alert; that is a true positive.
#   - doli: publishes at chat.dol.usai.gov (label `dol`, not the slug) and has no
#           working apex — 404 on every path. Synthetics disabled for it in
#           tenants.tf rather than monitoring a host that cannot pass.
# ---------------------------------------------------------------------------

locals {
  # DNS label under usai.gov. Usually the tenant slug, but not always — `doli`
  # publishes under `dol` — so it is a separate override (see var.edge_domain_label).
  edge_label = var.edge_domain_label != "" ? var.edge_domain_label : var.tenant

  # The apex host is where the chat UI and its /healthz endpoint now live after the
  # 2026-08 rename. Broken out as its own local because the health check targets
  # ONLY this host, while the TLS/reachability tests cover the full host list.
  edge_apex_host = "${local.edge_label}.usai.gov"

  # The API host. NOT renamed in the 2026-08 cutover (only chat.<label> collapsed
  # to the apex) and still serves its own /health returning {"status":true} — a
  # different path AND a different body shape from the apex's /healthz, which is
  # why api_health is its own resource in api_auth_synthetics.tf.
  edge_api_host = "api.${local.edge_label}.usai.gov"

  # Public edge hostnames per tenant: apex (was chat.<label>, now 301s to apex),
  # console, and api. All three verified to resolve and serve 200 on `/` across all
  # 15 enabled tenants (2026-08-19). Override via var.edge_hosts for any tenant
  # whose naming differs beyond the label.
  #
  # api was added 2026-08-19: it had TLS + reachability coverage in exactly one org
  # (ftc, hand-built in the UI) and none anywhere else, despite being the host the
  # chat frontend depends on. ftc's tests passing from aws:us-gov-west-1 is what
  # proves the host is reachable from the Datadog location.
  edge_hosts = length(var.edge_hosts) > 0 ? var.edge_hosts : [
    local.edge_apex_host,
    "console.${local.edge_label}.usai.gov",
    local.edge_api_host,
  ]

  # Only create synthetics when enabled AND a location is set. Both now default to
  # on/public — the private-location requirement was based on a WAF claim that
  # live evidence disproved (see the corrected caveat above).
  edge_synthetics_enabled = var.enable_edge_synthetics && length(var.synthetic_locations) > 0

  edge_hosts_effective = local.edge_synthetics_enabled ? local.edge_hosts : []

  # The app health check is apex-only on purpose. /healthz is NOT a universal
  # path: on console.<label>.usai.gov it 302-redirects to a login callback, and on
  # the API host it 404s (the API's health endpoint is still /health returning
  # {"status":true}). Iterating edge_hosts here would create a guaranteed-failing
  # console test, so this list is deliberately just the apex. Console and API
  # liveness is covered by https_reach below asserting 200 on `/`.
  edge_health_hosts = local.edge_synthetics_enabled ? [local.edge_apex_host] : []

  # cert_expiry_warn_days / cert_expiry_crit_days and the edge_synthetic_* timing
  # values live in locals.tf (the repo's single source of truth — GitHub #33).
}

# --- 0. App health check (/healthz) — replaces the 16 hand-built UI tests ----
# This is the Terraform-managed successor to the UI-created "Test on
# chat.<tenant>.usai.gov/health" / "Health Monitor" / "USDA Health Check
# Notification" synthetics that broke in the 2026-08 rename. It differs from those
# in four ways that matter, each one a repo convention they violated:
#
#   1. Target is the apex + /healthz + the "healthy" body shape (the rename fix).
#   2. The notification handle is scoped to {{#is_alert}} / {{#is_alert_recovery}}.
#      The UI tests put a bare handle on the FIRST line of the message, outside
#      every conditional, so it rendered on every state transition — the exact
#      flood PR #22 removed from the v0.1.0 monitors.
#   3. min_failure_duration 300s, not 0 — a single failed run cannot page.
#   4. renotify 60m, not 10m. usda's and ftc's 10m re-notify is what turned one
#      broken endpoint into a page every ten minutes per org.
#
# It also uses {{#is_alert_recovery}} rather than bare {{#is_recovery}}. There is
# no warn tier here (an endpoint is up or it is not), so bare would be safe today,
# but the UI tests used {{#is_recovery}} and the repo convention is to keep the
# handle on the critical path only.
resource "datadog_synthetics_test" "edge_health" {
  for_each = toset(local.edge_health_hosts)

  name      = "[${var.tenant}] App health check failing — ${each.value}/healthz"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = var.synthetic_locations
  message   = <<-EOT
    {{#is_alert}}
    The ${var.tenant} chat app is failing its health check: `https://${each.value}/healthz` has not returned a healthy response for ${local.edge_synthetic_min_failure_m} minutes. Users are likely seeing errors or a blank app.

    The endpoint returns `{"status":"healthy","checks":{"cache":...,"api":...}}` when well, so a failure is either the app being down/unready or one of its own dependencies (cache, upstream API) failing. Open the test result to see the status code and body.

    Triage order: check the deployment-availability and pod-restart-storm monitors for this tenant first (a stuck rollout explains most of these), then the upstream-API-unreachable monitor if the body shows the `api` check failing.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: ${each.value}/healthz is returning healthy again for ${var.tenant}.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Health endpoint: https://${each.value}/healthz
  EOT

  request_definition {
    method = "GET"
    url    = "https://${each.value}/healthz"
  }

  # 200 is necessary but not sufficient: assert the body too. A 200 with a
  # degraded payload is a real failure mode here because /healthz aggregates the
  # app's cache and upstream-API checks — that is precisely the signal the
  # stateoig outage needed and the readiness probe missed (see
  # frontend_upstream_api_unreachable below, which caught it from logs instead).
  assertion {
    type     = "statusCode"
    operator = "is"
    target   = 200
  }

  # `contains` rather than `is` so a future additive change to the status string
  # ("healthy (degraded cache)") does not turn into a false page, while a genuine
  # "unhealthy" still fails. Note the migration trap this replaces: the UI tests
  # asserted `$.status contains true` against the OLD {"status":true} payload,
  # which silently fails against the apex's {"status":"healthy"}.
  assertion {
    type     = "body"
    operator = "validatesJSONPath"
    targetjsonpath {
      jsonpath    = "$.status"
      operator    = "contains"
      targetvalue = "healthy"
    }
  }

  options_list {
    tick_every = local.edge_synthetic_tick_s
    # Follow redirects defensively. The apex serves /healthz directly today, so
    # this is not load-bearing — but it is exactly what the UI tests lacked when
    # chat.<label> started 301ing, and it costs nothing to be resilient to a
    # future host move.
    follow_redirects     = true
    min_failure_duration = local.edge_synthetic_min_failure_s
    min_location_failed  = 1
    retry {
      count    = 2
      interval = 30000
    }
    monitor_options {
      renotify_interval = local.edge_synthetic_renotify_min
    }
  }

  tags = concat(local.base_tags, ["service:edge-health", "check:app-healthz"])
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

  # Cert must be trusted AND have more than cert_expiry_crit_days left. For
  # subtype=ssl the `certificate` assertion's target is a number of DAYS, and
  # isInMoreThan asserts days-remaining > target. A missing / expired / untrusted
  # / self-signed cert fails the run at connection time (CERT_HAS_EXPIRED,
  # CERT_UNTRUSTED, INVALID_CA, DEPTH_ZERO_SELF_SIGNED_CERT) before assertions
  # are evaluated, so those cases are caught regardless. Hostname/SAN mismatch is
  # covered by the HTTP check (see file header).
  assertion {
    type     = "certificate"
    operator = "isInMoreThan"
    target   = local.cert_expiry_crit_days
  }

  options_list {
    tick_every           = local.edge_synthetic_tick_s
    accept_self_signed   = false
    min_failure_duration = local.edge_synthetic_min_failure_s
    min_location_failed  = 1
    retry {
      count    = 2
      interval = 30000
    }
    # A broken/expiring cert stays broken until someone rotates it, so re-page
    # daily rather than once — a single missed page means the cert lapses. Same
    # reasoning as cronjob_failing's 1440 in PR #39. Deliberately NOT the shared
    # edge_synthetic_renotify_min (60m): an expiring cert is a slow, days-long
    # countdown, so hourly nagging is pure noise where hourly is right for a
    # down endpoint.
    monitor_options {
      renotify_interval = 1440
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

  # statusCode only supports is/isNot operators. Follow redirects so the apex's
  # auth bounce (-> /auth/login -> Keycloak) resolves to a final 200, and so the
  # legacy chat.<label> 301 -> apex is followed rather than failing the assertion.
  # Console returns 200 directly. This also exercises the full TLS chain incl.
  # auth.usai.gov. A missing/bad cert or upstream drop fails the request before
  # any assertion is evaluated.
  assertion {
    type     = "statusCode"
    operator = "is"
    target   = 200
  }

  options_list {
    tick_every           = local.edge_synthetic_tick_s
    follow_redirects     = true
    min_failure_duration = local.edge_synthetic_min_failure_s
    min_location_failed  = 1
    retry {
      count    = 2
      interval = 30000
    }
    # Re-page hourly while the edge stays unreachable. Unlike the cert tests
    # (daily — a cert countdown moves slowly), an unreachable edge is an active
    # outage, so it shares the health check's cadence.
    monitor_options {
      renotify_interval = local.edge_synthetic_renotify_min
    }
  }

  tags = concat(local.base_tags, ["service:edge-tls", "check:https-reach"])
}

# --- 3. Cert-expiry early-warning (second SSL synthetic at 45 days) ---------
# Check 1 fails only once the cert is inside cert_expiry_crit_days (14). This
# test uses the SAME assertion form with the 45-day target, so a slowly-expiring
# cert surfaces with time to rotate (ACM generation + a PR is not instant).
#
# WHY A SECOND SYNTHETIC RATHER THAN A METRIC MONITOR: the first version of this
# was a `datadog_monitor` querying `synthetics.ssl.days_left{check_id:...}`.
# That metric DOES NOT EXIST. Verified against the live gov API (2026-08-04):
#   GET /api/v1/metrics/synthetics.ssl.days_left      -> {"errors":["... not found"]}
#   GET /api/v1/metrics/synthetics.ssl.time_to_expiry -> exists, unit: MINUTE
# So the query returned no series and — with notify_no_data = false — the monitor
# would have sat in No Data forever, displaying green while monitoring nothing.
# That is strictly worse than the EEOC gap it was meant to close: previously no
# monitor, now a monitor that LOOKS like it works. (The live test-apply to eeoc
# did not catch this: Datadog accepts a monitor on any metric name and simply
# parks it in No Data, so the apply proved only that the query grammar parsed.)
#
# Even with the correct name the thresholds would have been wrong: time_to_expiry
# is in MINUTES, so `< 14` means "expires in 14 minutes", not 14 days.
#
# Reusing the `certificate` / `isInMoreThan` assertion avoids the metric name,
# the unit conversion, AND the unverified `check_id` tag key in one move — it is
# the one form the provider docs explicitly demonstrate for SSL tests.
#
# Handle-less by design: a cert 45 days out is a ticket, not a page. Only the
# 14-day test (check 1) carries the notification handle.
resource "datadog_synthetics_test" "ssl_cert_expiring_soon" {
  for_each = toset(local.edge_hosts_effective)

  name      = "[${var.tenant}] Edge TLS cert expiring soon (<${local.cert_expiry_warn_days}d) — ${each.value}"
  type      = "api"
  subtype   = "ssl"
  status    = "live"
  locations = var.synthetic_locations
  message   = <<-EOT
    {{#is_alert}}
    TLS certificate for ${each.value} (${var.tenant}) expires in fewer than ${local.cert_expiry_warn_days} days. Rotate/renew via ACM before it breaks client access — cert generation plus a PR takes time, so do not wait for the hard failure. No page is sent for this tier; the ${local.cert_expiry_crit_days}-day test pages.
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: cert for ${each.value} renewed — more than ${local.cert_expiry_warn_days} days remaining.
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Edge host: ${each.value}
  EOT

  request_definition {
    host = each.value
    port = "443"
  }

  assertion {
    type     = "certificate"
    operator = "isInMoreThan"
    target   = local.cert_expiry_warn_days
  }

  options_list {
    tick_every           = 3600 # hourly is ample for a 45-day countdown
    accept_self_signed   = false
    min_failure_duration = local.edge_synthetic_min_failure_s
    min_location_failed  = 1
  }

  tags = concat(local.base_tags, ["service:edge-tls", "check:cert-expiry"])
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
# to solve, not a missing-metric one.
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
    {{#is_no_data_recovery}}
    Recovered: ACM cert-expiry metric is reporting again for ${var.tenant}.
    ${var.notification_channel}
    {{/is_no_data_recovery}}
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

  # notify_no_data is FALSE on purpose while this monitor is unverified: it has
  # never successfully evaluated (see header), so a premature rollout would have
  # every tenant page on No Data. Flipping this to true is an EXPLICIT step in
  # the verification checklist above — do it only after confirming the monitor
  # reaches OK on one tenant. No-data IS a meaningful signal here (a tenant with
  # no AWS integration has unmonitored certs), so true is the eventual target,
  # just not before the No-Data root cause is understood.
  notify_no_data    = false
  no_data_timeframe = 1440 # 24h — ACM metric is ~hourly+sparse; only a genuine
  # integration outage (not a scrape gap) should trip no-data. 2h would false-page.
  renotify_interval = 1440 # daily reminder: an expiring cert stays expiring until
  # someone rotates it, so a single page that gets missed means the cert lapses.
  # service:acm, not service:edge-tls — this reads the AWS/CloudWatch integration
  # metric rather than probing the edge, so it shouldn't be swept up by an
  # edge-TLS scoped mute or dashboard filter.
  tags = concat(local.base_tags, ["service:acm", "check:acm-cert-expiry"])
}

# ---------------------------------------------------------------------------
# Frontend -> upstream API unreachable (server-side TLS/connect failure)
# ---------------------------------------------------------------------------
# Added after a 2026-08-13 stateoig outage that BOTH mechanisms above would have
# missed. The chat-beta frontend's server-side fetch to its own API died in the
# TLS handshake for ~25h (from 2026-08-12T15:04Z) and nothing alerted:
#
#   TypeError: fetch failed
#   caused by: Error [ERR_TLS_CERT_ALTNAME_INVALID]: Hostname/IP does not match
#     certificate's altnames: Host: api.beta.prod.stateoig.mcaas.fcs.gsa.gov
#     is not in the cert's altnames: DNS:*.prod.stateoig.mcaas.fcs.gsa.gov
#
# A wildcard cert matches ONE label, so `api.beta.prod.<tenant>` is not covered by
# `*.prod.<tenant>`. Tenants onboarded to chat-beta before 2026-08 have a deeper
# `*.beta.prod.<tenant>` cert; the 10 onboarded on 2026-08-13 do not. Users saw
# 502 on /backend/chat/v1/* (envoy relaying the app's own failure via_upstream).
#
# WHY THE SYNTHETICS ABOVE DON'T FULLY COVER IT:
#   - They probe the EDGE from outside. This break is a POD-INTERNAL egress call,
#     invisible to an external prober even when the edge is perfectly healthy.
#   - Their edge_hosts default is <label>.usai.gov + console.<label>.usai.gov —
#     the failing host (api.beta.prod.<tenant>.mcaas.fcs.gsa.gov) is not in that
#     list, and would not be a sensible thing to probe from a public location.
# (Two claims that WERE here are now obsolete: the synthetics are no longer "gated
# off pending a private location" — that gate was based on a disproven WAF claim,
# see the header — and the edge_health check added above DOES now assert the
# /healthz body, so a degraded `api` dependency check is visible externally. This
# log monitor is still the durable safety net: it names the failing host and the
# TLS error, and it fires even if /healthz keeps returning 200.)
#
# WHY /healthz DIDN'T CATCH IT: the frontend logs this at `warn` from its health
# handler but still returns 200, so the readiness probe passed, no pod was marked
# unready, and deployment-availability monitors stayed green for a full day. The
# durable fix is making that health check fail when its API dependency is
# unreachable (tracked separately in the frontend repo); this monitor is the
# safety net that pages regardless of what the probe reports.
#
# ── WHY A RATIO, NOT A COUNT (this monitor was reverted once for it) ─────────
# The first version of this used an absolute count (>20 in 10m) on the reasoning
# that a fixed-cadence health-check log doesn't scale with tenant size. That was
# WRONG and it flooded ~200 alerts across the 25 orgs on first apply, so the
# monitors were destroyed and redesigned. Two things were missed:
#
#   1. The log is emitted ~24x/MINUTE per pod (240 per 10m — measured, dead
#      steady across a 1h53m incident). A >20-in-10m threshold is therefore
#      breached by a SINGLE pod in under a minute. It was never a 10% margin.
#   2. The count DOES scale — with pod count, not tenant size. A failing rollout
#      that CrashLoopBackOffs, or an HPA scaling up, multiplies emitters. Exactly
#      the transient conditions that must NOT page are the ones that inflate an
#      absolute count fastest.
#
# So this is a RATIO of failing health checks to total health checks. Measured on
# the stateoig incident vs. the same pod healthy 20 minutes later:
#
#            healthz requests   failures   ratio
#   broken         240            240      100.0%
#   healthy        232              0        0.0%
#
# The ratio is pod-count-INVARIANT: 1 pod or 20, a broken upstream is ~100% and a
# healthy one is 0%. A restart storm or scale event changes the denominator and
# the numerator together, so it does not move the ratio. That is the property an
# absolute count lacks, and it is why the repo's prefer-rates-over-counts rule
# exists — this monitor originally violated it and paid for it.
#
# A 30m window with require_full_window means a short crashloop or a rollout blip
# (both of which recover well inside 30m, and both of which fail 100% only while
# actually down) cannot sustain the ratio long enough to page. Critical 90% (not
# 100%) tolerates a few interleaved successes during pod churn.
resource "datadog_monitor" "frontend_upstream_api_unreachable" {
  name = "[${var.tenant}] Frontend - upstream API unreachable (TLS/connect failure)"
  type = "log alert"

  # Ratio of failed dependency checks to total health checks. Log-alert ratios
  # require formula() + an options.variables list; the inline
  # `logs(...) / logs(...)` form does NOT parse (verified against the live gov
  # API: 400 "unable to parse log monitor query").
  query = "formula(\"(failed / total) * 100\").last(\"30m\") > 90"

  variables {
    event_query {
      name        = "failed"
      data_source = "logs"
      indexes     = ["*"]
      compute {
        aggregation = "count"
      }
      search {
        query = "env:production service:usai-frontend \"API connection failed\""
      }
    }
    event_query {
      name        = "total"
      data_source = "logs"
      indexes     = ["*"]
      compute {
        aggregation = "count"
      }
      search {
        query = "env:production service:usai-frontend \"Incoming request: GET /healthz\""
      }
    }
  }

  message = <<-EOT
    {{#is_alert}}
    The chat-beta frontend cannot reach its upstream API — {{value}}% of its health checks have failed the dependency call for 30 minutes. Users get **502** on /backend/chat/v1/* even though the edge and /healthz look healthy, because the failing call is the frontend's own server-side fetch.

    Sustained for 30m at ~100%, so this is not a rollout blip or a scaling event (those move numerator and denominator together and recover well inside the window). Most likely a TLS certificate that does not cover the API hostname: `USAI_API_URL` is `api.beta.<env>.<tenant>.mcaas.fcs.gsa.gov`, and a `*.prod.<tenant>` wildcard does NOT match it (a wildcard covers one label). This was the 2026-08-13 stateoig outage.

    Triage: open a log event and read `@err.stack` — `ERR_TLS_CERT_ALTNAME_INVALID` names both the requested host and the cert's actual altnames. Confirm with:
    `openssl s_client -connect <api-host>:443 -servername <api-host> | openssl x509 -noout -ext subjectAltName`
    Fix by issuing a cert covering the API hostname (or pointing `USAI_API_URL` at a cert-valid name). Note: searching the bare string ERR_TLS_CERT_ALTNAME_INVALID returns nothing — it lives in the nested `err.stack` attribute; search `"API connection failed"` instead.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: the frontend can reach its upstream API again for ${var.tenant}.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Ratio: "API connection failed" / "GET /healthz" over 30m
  EOT

  # No warn tier: the ratio is bimodal (0% healthy / ~100% broken — measured), so
  # an intermediate "warning" band has no meaningful occupancy and would only add
  # noise. With no warn tier, {{#is_alert_recovery}} is still used deliberately
  # (never bare {{#is_recovery}}) to keep the handle on the critical path only.
  monitor_thresholds {
    critical = 90
    # Recover at 10%: well below the 90% trigger and far above the 0% healthy
    # baseline, so pod churn during the fix cannot flap Alert<->OK.
    critical_recovery = 10
  }

  include_tags = false
  notify_audit = false

  # Require the full 30m window before evaluating. This is the primary guard
  # against paging on a failing rollout / crashloop / scale event: a pod that
  # comes up broken and is replaced does not produce 30 continuous minutes of
  # ~100% failure.
  require_full_window = true

  # No-data must NOT alert: a tenant not yet running chat-beta emits no
  # usai-frontend logs at all (and the ratio's denominator would be 0), so a
  # no-data page would fire for every such tenant. `on_missing_data` ("default" =
  # evaluate as not-breaching, never notify on no-data) is the provider-supported
  # way to express this and matches the other log alerts in this repo — it
  # CONFLICTS with `notify_no_data`, so only this one is set.
  on_missing_data = "default"

  # NO renotify_interval. The first version set 1440 ("re-page daily while
  # broken"), which combined with 25 tenants alerting at once produced the ~200
  # alert flood. A cert lapse is already covered by the daily-renotifying cert
  # monitors above; this monitor pages once per genuine transition, which is
  # enough to open an incident.

  tags = concat(local.base_tags, ["service:edge-tls", "check:upstream-api-reachability"])
}
