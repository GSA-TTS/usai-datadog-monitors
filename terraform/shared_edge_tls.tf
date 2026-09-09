# ---------------------------------------------------------------------------
# Shared aigov edge TLS — auth.usai.gov
#
# WHY THIS IS NOT IN modules/model_backend_monitors: the module's cert checks are
# per-tenant and apex-only (`cert_hosts = [local.edge_apex_host]`), so they cover
# `<label>.usai.gov` and nothing else. `auth.usai.gov` is the shared Keycloak that
# all 25 tenants authenticate against — it belongs to no tenant, so no module
# instance ever checks its certificate. Its only coverage before this file was the
# HTTP realm check (`api_auth_synthetics.tf`, keycloak_realm), and an HTTP test
# cannot detect an incomplete chain because Datadog's
# disable_aia_intermediate_fetching option is documented as SSL-test-scoped.
#
# THE INCIDENT THIS CLOSES (2026-09-09): auth.usai.gov was serving ONLY the
# CN=usai.gov leaf — SSL Labs "This server's certificate chain is incomplete ...
# Certificates provided: 1" — because the ACM cert on aigov-core-prod-alb is an
# IMPORTED cert served without its `Amazon RSA 2048 M04` intermediate. Browsers
# fetch the intermediate via AIA and were unaffected, which is why three months
# passed with no signal. Okta's Java SCIM connector does not, and failed FAA's
# provisioning setup with `PKIX path building failed`. Full write-up:
# usai-main/docs/RCA_AUTH_USAI_GOV_INCOMPLETE_TLS_CHAIN.md
#
# ONE TEST, NOT THREE — the same reasoning as the module's 2026-08-19 cert
# dedup. One ACM cert carries `usai.gov`, `www.usai.gov` and `auth.usai.gov`
# (verified via `aws acm describe-certificate` on both the IMPORTED cb131f17-…
# and the AMAZON_ISSUED aaef1acf-… that should replace it), and the ALB serves it
# by SNI for all three names. Testing one name therefore tests the certificate.
# If those names are ever split across separate certs, add them here.
#
# LOCATION MUST STAY PUBLIC. `auth.usai.gov` is split-horizon DNS: internally it
# resolves to 100.64.1.56, an Istio ingress whose Kubernetes secret DOES contain
# the full chain, so it verifies cleanly. A private location (`pl:…`) would probe
# that terminator and pass while the public ALB stayed broken — the monitor would
# reinforce exactly the false confidence that let this incident run for months.
# ---------------------------------------------------------------------------

locals {
  # The shared Keycloak hostname. Not derived from a tenant label — this is aigov
  # infrastructure, and the same host appears in api_auth_synthetics.tf's realm
  # check for all 25 tenants.
  aigov_auth_host = "auth.usai.gov"

  # Mirrors of modules/model_backend_monitors/locals.tf. Duplicated deliberately:
  # module locals are not readable from the root module, and adding a variable to
  # thread them through would couple the shared aigov checks to the per-tenant
  # module for two integers. Keep the values in step with that file.
  aigov_cert_expiry_crit_days        = 14  # crit — genuinely close, page it
  aigov_edge_synthetic_tick_s        = 300 # run every 5m
  aigov_edge_synthetic_min_failure_s = 300 # must fail continuously 5m before alerting

  # Public GovCloud managed location — the same default the module uses, verified
  # to reach these endpoints. See the LOCATION MUST STAY PUBLIC note above.
  aigov_synthetic_locations = ["aws:us-gov-west-1"]
}

resource "datadog_synthetics_test" "aigov_auth_edge_tls" {
  provider  = datadog.aigov
  name      = "Keycloak edge TLS — ${local.aigov_auth_host} cert invalid, chain incomplete, or expiring"
  type      = "api"
  subtype   = "ssl"
  status    = "live"
  locations = local.aigov_synthetic_locations
  message   = <<-EOT
    {{#is_alert}}
    TLS certificate check FAILED for https://${local.aigov_auth_host}: the served certificate is missing, does not match the hostname, is untrusted, is expiring within ${local.aigov_cert_expiry_crit_days} days, or the server is not sending its full chain.

    This is the shared Keycloak every tenant authenticates against, so partner integrations break platform-wide, not per-tenant. Browsers may keep working even while this alerts — they fetch missing intermediates via AIA, Java/Go/Node/OpenSSL clients do not.

    Confirm from OUTSIDE the GSA network (internal DNS reaches a different terminator that always looks healthy):
    https://www.ssllabs.com/ssltest/analyze.html?d=${local.aigov_auth_host}&clearCache=on
    Expect "Certificates provided: 2" or more and "Chain issues: None".

    Runbook: usai-main/docs/TLS_PKIX_TROUBLESHOOTING.md
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: TLS certificate and chain for ${local.aigov_auth_host} are valid again.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: aigov (shared) @ Edge host: ${local.aigov_auth_host}
  EOT

  request_definition {
    host = local.aigov_auth_host
    port = "443"
  }

  # For subtype=ssl the `certificate` assertion target is a number of DAYS, and
  # isInMoreThan asserts days-remaining > target. Missing / expired / untrusted /
  # self-signed certs fail at connection time before assertions run, so they are
  # caught regardless of this assertion.
  assertion {
    type     = "certificate"
    operator = "isInMoreThan"
    target   = local.aigov_cert_expiry_crit_days
  }

  options_list {
    tick_every         = local.aigov_edge_synthetic_tick_s
    accept_self_signed = false

    # The whole point of this file. Off by default, which means Datadog completes
    # a partial chain via AIA and a leaf-only server passes every other check.
    disable_aia_intermediate_fetching = true

    min_failure_duration = local.aigov_edge_synthetic_min_failure_s
    min_location_failed  = 1
    retry {
      count    = 2
      interval = 30000
    }
    # Daily, not hourly: a broken chain or an expiring cert stays broken until
    # someone rotates or reattaches a certificate. Same reasoning as the module's
    # ssl_cert renotify_interval.
    monitor_options {
      renotify_interval = 1440
    }
  }

  # `service:keycloak` matches the other aigov-scope resources in monitors.tf /
  # dashboard.tf rather than the module's `service:edge-tls` — one service key, not
  # two (nothing filters on edge-tls today; `check:ssl-cert` is what identifies the
  # check type).
  tags = ["managed-by:terraform", "platform:usai", "tenant:aigov", "service:keycloak", "check:ssl-cert"]
}
