# ---------------------------------------------------------------------------
# API + Keycloak-realm synthetics
# ---------------------------------------------------------------------------
# Two coverage gaps found on 2026-08-19 while auditing the hand-built UI tests
# left over from the <tenant>.usai.gov cutover. Both existed in exactly ONE org
# each and nowhere else, despite covering dependencies every tenant shares:
#
#   * ftc had "API Health Monitor" + "API SSL Certificate" on api.ftc.usai.gov.
#   * doj had "Keycloak Realm Monitor" on auth.usai.gov/realms/doj.
#
# Both were passing from the PUBLIC aws:us-gov-west-1 location, which is the
# evidence that these hosts are reachable from the Datadog location — the one
# thing laptop curl cannot establish (see the PR #44 note in cert_monitors.tf).
# Generalising them here replaces the one-off UI tests with per-tenant coverage.
#
# TLS/reachability for the api host is NOT here — api.<label> was added to
# local.edge_hosts in cert_monitors.tf, so it inherits ssl_cert, https_reach and
# ssl_cert_expiring_soon automatically.
#
# Gated by the same local.edge_synthetics_enabled as the rest, so the 8
# WAF-unreachable tenants and doli/ang create nothing.
# ---------------------------------------------------------------------------

# --- API health (api.<label>.usai.gov/health) -------------------------------
# The chat frontend's server-side fetch targets this API. When it fails, users get
# 502s on /backend/chat/v1/* while the edge and the apex /healthz can both still
# look green — the 2026-08-13 stateoig outage. That outage is covered from the logs
# side by frontend_upstream_api_unreachable; this is the external black-box view of
# the same dependency, and it needs no app logging to work.
#
# WHY NOT FOLDED INTO edge_health: the API's contract is different from the apex's
# on both axes — path /health vs /healthz, body {"status":true} vs
# {"status":"healthy"}. Verified across all 15 enabled tenants 2026-08-19.
#
# ── INTERMITTENT 503s ARE EXPECTED HERE (do not "fix" by loosening) ──────────
# api.<label>/health returns sporadic `503 upstream connect error` — measured on
# hhs at roughly 1-in-3 on one sample, then 1-in-3 again minutes later, while opm
# showed a single 503 and then recovered. The apex /healthz reports
# `checks.api: healthy` throughout, because the frontend reaches the API by an
# internal URL rather than this public host.
#
# The retry(2) + min_failure_duration(300s) combination is what makes this test
# usable against that flakiness: a run fails only if all 3 attempts fail, and the
# monitor pages only after 5 continuous minutes of failed runs — so a ~1/3 blip
# rate does not page, while a genuinely dead upstream does. Do NOT drop the retries
# or shorten min_failure_duration; that is what would turn this into a flapper.
# Conversely, do not read this monitor as proof the API is 100% healthy — partial
# 5xx rates are an envoy/ingress-rate question, not a black-box up/down one.
resource "datadog_synthetics_test" "api_health" {
  for_each = toset(local.edge_synthetics_enabled ? [local.edge_api_host] : [])

  name      = "[${var.tenant}] API health check failing — ${each.value}/health"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = var.synthetic_locations
  message   = <<-EOT
    {{#is_alert}}
    The ${var.tenant} API is failing its health check: `https://${each.value}/health` has not returned a healthy response for ${local.edge_synthetic_min_failure_m} minutes. This is the API the chat frontend calls server-side, so users are likely seeing **502** on /backend/chat/v1/* even if the chat page itself loads.

    Sustained for ${local.edge_synthetic_min_failure_m}m through 2 retries, so this is NOT the sporadic `503 upstream connect error` this endpoint normally emits — it means no healthy API upstream.

    Triage: check the deployment-availability monitor for `api` in `core-api`, then pod events. Cross-check the upstream-API-unreachable log monitor, which sees the same failure from inside the frontend pod.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: ${each.value}/health is healthy again for ${var.tenant}.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ API health endpoint: https://${each.value}/health
  EOT

  request_definition {
    method = "GET"
    url    = "https://${each.value}/health"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = 200
  }

  # Body is {"status":true} — a BOOLEAN, not the apex's "healthy" string. `contains`
  # against "true" is the form ftc's UI test used successfully against this exact
  # payload, so it is mirrored rather than re-derived.
  assertion {
    type     = "body"
    operator = "validatesJSONPath"
    targetjsonpath {
      jsonpath    = "$.status"
      operator    = "contains"
      targetvalue = "true"
    }
  }

  options_list {
    tick_every           = local.edge_synthetic_tick_s
    follow_redirects     = true
    min_failure_duration = local.edge_synthetic_min_failure_s
    min_location_failed  = 1
    # Load-bearing against the intermittent 503s described above — not boilerplate.
    retry {
      count    = 2
      interval = 30000
    }
    monitor_options {
      renotify_interval = local.edge_synthetic_renotify_min
    }
  }

  tags = concat(local.base_tags, ["service:edge-api", "check:api-health"])
}

# --- Keycloak realm availability (auth.usai.gov/realms/<label>) --------------
# Every tenant authenticates against the SHARED Keycloak in the aigov org, so a
# realm that stops serving its public config breaks login for that tenant while
# the tenant's own app and edge stay perfectly healthy — invisible to every other
# monitor in this module.
#
# WHY PER-TENANT RATHER THAN ONE MONITOR IN aigov: the aigov org already has
# Keycloak monitors (monitors.tf), but they are login-EVENT log alerts across all
# realms — they answer "are logins failing in aggregate", not "is tenant X's realm
# reachable". A per-realm probe fails for one tenant only, alerts in that tenant's
# own org, and names the tenant. The realm slug equals the tenant slug for all 15
# enabled tenants (verified 2026-08-19: every /realms/<slug> returns 200 with a
# matching "realm" field).
#
# NOTE the shared dependency: 15 tenants each probing auth.usai.gov every 5m means
# a Keycloak outage lights up 15 orgs at once. That is correct — it IS a
# 15-tenant outage — but expect the fan-out and treat simultaneous firing across
# many orgs as one incident, not fifteen.
# ── GATED SEPARATELY FROM THE EDGE SYNTHETICS, ON PURPOSE ───────────────────
# This is the one synthetic that does NOT depend on local.edge_synthetics_enabled.
# Its target is auth.usai.gov — shared aigov infrastructure — not the tenant's own
# edge, so the per-tenant WAF reachability that blocks 8 tenants (dnfsb, doj, faa,
# nrc, ntsb, oge, nsf, eeoc) does not apply. Proof: doj is one of those 8, and its
# hand-built Keycloak Realm Monitor has been passing from aws:us-gov-west-1 the
# whole time its edge was unreachable.
#
# So all 25 tenants get login-path coverage, including the 8 that can have no edge
# monitoring at all and doli/ang which aren't serving. Realms verified to exist and
# return a matching name for all 25 on 2026-08-19 — including doli, whose realm is
# `dol` (its DNS label), NOT `doli` (/realms/doli is a 404). That is exactly why
# this keys off local.edge_label rather than var.tenant.
resource "datadog_synthetics_test" "keycloak_realm" {
  for_each = toset(var.enable_keycloak_realm_synthetic && length(var.synthetic_locations) > 0 ? [local.edge_label] : [])

  name      = "[${var.tenant}] Keycloak realm unavailable — auth.usai.gov/realms/${each.value}"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = var.synthetic_locations
  message   = <<-EOT
    {{#is_alert}}
    The Keycloak realm for ${var.tenant} is not serving its public configuration: `https://auth.usai.gov/realms/${each.value}` has been failing for ${local.edge_synthetic_min_failure_m} minutes. **Users cannot log in to ${var.tenant}**, even though the tenant's own app and edge may look healthy — Keycloak is shared infrastructure in the aigov org, not this tenant's cluster.

    If this is firing for MANY tenants at once it is a single shared-Keycloak incident, not one per tenant. Check the aigov org's Keycloak monitors and dashboard first.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: Keycloak realm ${each.value} is serving again.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Realm endpoint: https://auth.usai.gov/realms/${each.value}
  EOT

  request_definition {
    method = "GET"
    url    = "https://auth.usai.gov/realms/${each.value}"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = 200
  }

  # Assert the realm NAME, not just a 200. Keycloak answers /realms/<anything> with
  # a 200 + JSON for any existing realm, so a 200 alone would not catch a
  # misrouted/renamed realm — only that *some* realm replied.
  assertion {
    type     = "body"
    operator = "validatesJSONPath"
    targetjsonpath {
      jsonpath    = "$.realm"
      operator    = "is"
      targetvalue = each.value
    }
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
    monitor_options {
      renotify_interval = local.edge_synthetic_renotify_min
    }
  }

  tags = concat(local.base_tags, ["service:keycloak", "check:realm-availability"])
}
