# ---------------------------------------------------------------------------
# Shared-Keycloak monitors (aigov org). These are org-wide, not per-tenant —
# aigov hosts the Keycloak all 25 tenants authenticate against, so one alert here
# means every tenant's login path is affected.
#
# ── FIXED 2026-08-19: BARE NOTIFICATION HANDLES (the PR #22 bug, again) ──────
# All five monitors below had `${var.notification_channel}` as a TRAILING line,
# outside every conditional block. Datadog renders the whole message on every
# state transition, so the handle fired on Warn, on Recovered, AND on Triggered.
# On 2026-08-19 a 4-minute transient login-error spike produced SIX emails
# (Warn, Warn, Recovered, Warn, Recovered, Recovered) from two monitors.
#
# This is the exact bug PR #22 removed from the per-tenant monitors, and the
# reason CLAUDE.md carries the "scope the handle to {{#is_alert}}" rule. These
# five were missed because they live in the ROOT module (aigov-only) rather than
# modules/model_backend_monitors, so the PR #22 sweep never touched them. If you
# add a monitor here, it needs the same treatment — the convention applies to the
# root module too.
#
# Warn tiers are now deliberately handle-less (a dashboard signal, not a page) and
# recovery uses {{#is_alert_recovery}}, never bare {{#is_recovery}} — with a warn
# tier set, bare would still page on WARN->OK.
#
# ── KNOWN REDUNDANCY: THREE MONITORS, ONE QUERY (not fixed here) ─────────────
# keycloak_login_failures_spike (>20), keycloak_login_success_rate_drop (>40) and
# keycloak_top_failing_clients_spike (>15) run the IDENTICAL query — a 5m rollup
# count of `type=LOGIN_ERROR env:production` — at three thresholds. One spike can
# therefore page up to three times, which is what the 2026-08-19 flap did (both
# >20 and >15 fired at 10:06). Two are also misnamed for what they measure:
# "success rate drop" computes no rate, and "top failing clients" has no
# `by {client}` grouping, so neither can deliver what its name promises.
#
# Left in place deliberately: collapsing them into one tiered monitor (plus a real
# by-client grouping and a genuine LOGIN_ERROR/LOGIN ratio) changes what gets
# alerted on, which is a monitoring-design decision rather than a noise fix, and
# this PR is scoped to the handle bug. The in-message NOTEs above tell whoever
# gets paged what the monitor actually measures in the meantime.
# ---------------------------------------------------------------------------
resource "datadog_monitor" "keycloak_login_failures_spike" {
  provider = datadog.aigov
  name     = "Keycloak - Login Failures Spike (>20 in 5 min)"
  type     = "log alert"
  query    = "logs(\"service:keycloak \\\"org.keycloak.events\\\" type=LOGIN_ERROR env:production\").index(\"*\").rollup(\"count\").last(\"5m\") > 20"
  message  = <<-EOT
    {{#is_alert}}
    Keycloak login failures have exceeded the threshold of 20 in the last 5 minutes. This may indicate a brute-force attack or credential stuffing attempt. Please investigate immediately.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_warning}}
    Elevated Keycloak login failures ({{value}} in 5m, warn tier at 10). Below the paging threshold — no action required unless it climbs. Deliberately handle-less.
    {{/is_warning}}
    {{#is_alert_recovery}}
    Recovered: Keycloak login failures back below threshold.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Environment: production @ Query: service:keycloak type=LOGIN_ERROR
  EOT

  monitor_thresholds {
    critical = 20
    warning  = 10
  }

  include_tags           = false
  notify_audit           = false
  on_missing_data        = "default"
  groupby_simple_monitor = false

  tags = ["managed-by:terraform", "service:keycloak", "tenant:aigov"]

  # Preserve the runbook notebooks operators attached in the UI. `assets` is an
  # optional block on datadog_monitor, so with none declared here Terraform would
  # send an empty list and DELETE those links — a plan on 2026-08-18 showed exactly
  # that (assets: [{runbook /notebook/20715...}] -> []) across all five monitors.
  # Runbooks are real operator work and are not modelled in this repo, so they are
  # ignored rather than clobbered.
  lifecycle {
    ignore_changes = [assets]
  }
}

resource "datadog_monitor" "keycloak_login_success_rate_drop" {
  provider = datadog.aigov
  name     = "Keycloak - Login Success Rate Drop (High Error Volume)"
  type     = "log alert"
  query    = "logs(\"service:keycloak \\\"org.keycloak.events\\\" type=LOGIN_ERROR env:production\").index(\"*\").rollup(\"count\").last(\"5m\") > 40"
  message  = <<-EOT
    {{#is_alert}}
    Keycloak login error count has exceeded 40 in the last 5 minutes — roughly double the login-failures threshold, so treat this as the severe tier of the same signal. This could signal an authentication service issue or an ongoing attack. Please investigate immediately.

    NOTE: despite the monitor name this does NOT compute a success rate — it is a raw LOGIN_ERROR count, so it reads high during a traffic spike even if the success *rate* is healthy. Cross-check total LOGIN vs LOGIN_ERROR on the Keycloak dashboard before concluding a rate drop. (Tracked for consolidation — see the header note in this file.)
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_warning}}
    Keycloak login errors elevated ({{value}} in 5m, warn tier at 20). Handle-less by design.
    {{/is_warning}}
    {{#is_alert_recovery}}
    Recovered: Keycloak login error volume back below threshold.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Environment: production
  EOT

  monitor_thresholds {
    critical = 40
    warning  = 20
  }

  include_tags           = false
  notify_audit           = false
  on_missing_data        = "default"
  groupby_simple_monitor = false

  tags = ["managed-by:terraform", "service:keycloak", "tenant:aigov"]

  # Preserve the runbook notebooks operators attached in the UI. `assets` is an
  # optional block on datadog_monitor, so with none declared here Terraform would
  # send an empty list and DELETE those links — a plan on 2026-08-18 showed exactly
  # that (assets: [{runbook /notebook/20715...}] -> []) across all five monitors.
  # Runbooks are real operator work and are not modelled in this repo, so they are
  # ignored rather than clobbered.
  lifecycle {
    ignore_changes = [assets]
  }
}

resource "datadog_monitor" "keycloak_invalid_credentials_spike" {
  provider = datadog.aigov
  name     = "Keycloak - Invalid Credentials Error Spike (>10 in 5 min)"
  type     = "log alert"
  query    = "logs(\"service:keycloak \\\"org.keycloak.events\\\" type=LOGIN_ERROR error=invalid_user_credentials env:production\").index(\"*\").rollup(\"count\").last(\"5m\") > 10"
  message  = <<-EOT
    {{#is_alert}}
    Keycloak invalid_user_credentials errors have exceeded 10 in the last 5 minutes. This may indicate credential stuffing, a brute force attack, or a misconfigured client application. Please review the source IPs and affected users.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_warning}}
    Elevated invalid-credential errors ({{value}} in 5m, warn tier at 5). Handle-less by design.
    {{/is_warning}}
    {{#is_alert_recovery}}
    Recovered: invalid_user_credentials errors back below threshold.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Environment: production
  EOT

  monitor_thresholds {
    critical = 10
    warning  = 5
  }

  include_tags           = false
  notify_audit           = false
  on_missing_data        = "default"
  groupby_simple_monitor = false

  tags = ["managed-by:terraform", "service:keycloak", "tenant:aigov"]

  # Preserve the runbook notebooks operators attached in the UI. `assets` is an
  # optional block on datadog_monitor, so with none declared here Terraform would
  # send an empty list and DELETE those links — a plan on 2026-08-18 showed exactly
  # that (assets: [{runbook /notebook/20715...}] -> []) across all five monitors.
  # Runbooks are real operator work and are not modelled in this repo, so they are
  # ignored rather than clobbered.
  lifecycle {
    ignore_changes = [assets]
  }
}

resource "datadog_monitor" "keycloak_active_users_drop" {
  provider = datadog.aigov
  name     = "Keycloak - Active Users Drop (Login Activity Below Normal)"
  type     = "log alert"
  query    = "logs(\"service:keycloak \\\"org.keycloak.events\\\" type=LOGIN env:production\").index(\"*\").rollup(\"count\").last(\"30m\") < 2"
  message  = <<-EOT
    {{#is_alert}}
    Keycloak login activity has dropped below 2 events in the last 30 minutes. This may indicate an authentication service outage or connectivity issue — no logins across ALL tenants is a shared-Keycloak failure. Please check the Keycloak service health immediately.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_warning}}
    Keycloak login activity is low ({{value}} in 30m, warn tier at 5). Expected overnight and at weekends — this is a "less than" monitor, so the warn tier sits ABOVE the critical one. Handle-less by design.
    {{/is_warning}}
    {{#is_alert_recovery}}
    Recovered: Keycloak login activity back to normal levels.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Environment: production
  EOT

  monitor_thresholds {
    critical = 2
    warning  = 5
  }

  include_tags           = false
  notify_audit           = false
  on_missing_data        = "default"
  groupby_simple_monitor = false

  tags = ["managed-by:terraform", "service:keycloak", "tenant:aigov"]

  # Preserve the runbook notebooks operators attached in the UI. `assets` is an
  # optional block on datadog_monitor, so with none declared here Terraform would
  # send an empty list and DELETE those links — a plan on 2026-08-18 showed exactly
  # that (assets: [{runbook /notebook/20715...}] -> []) across all five monitors.
  # Runbooks are real operator work and are not modelled in this repo, so they are
  # ignored rather than clobbered.
  lifecycle {
    ignore_changes = [assets]
  }
}

resource "datadog_monitor" "keycloak_top_failing_clients_spike" {
  provider = datadog.aigov
  name     = "Keycloak - Top Failing Clients Spike (>15 errors in 5 min)"
  type     = "log alert"
  query    = "logs(\"service:keycloak \\\"org.keycloak.events\\\" type=LOGIN_ERROR env:production\").index(\"*\").rollup(\"count\").last(\"5m\") > 15"
  message  = <<-EOT
    {{#is_alert}}
    Keycloak login errors have exceeded 15 in the last 5 minutes across client applications. Please check the Top Failing Clients widget in the Keycloak dashboard and review client configurations.

    NOTE: despite the monitor name this is NOT grouped by client — the query has no `by {client}`, so it cannot name the offending client and will fire on aggregate error volume from any source. Use the dashboard widget for attribution. (Tracked for consolidation — see the header note in this file.)
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_warning}}
    Client login errors elevated ({{value}} in 5m, warn tier at 8). Handle-less by design.
    {{/is_warning}}
    {{#is_alert_recovery}}
    Recovered: client login errors back below threshold.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Environment: production
  EOT

  monitor_thresholds {
    critical = 15
    warning  = 8
  }

  include_tags           = false
  notify_audit           = false
  on_missing_data        = "default"
  groupby_simple_monitor = false

  tags = ["managed-by:terraform", "service:keycloak", "tenant:aigov"]

  # Preserve the runbook notebooks operators attached in the UI. `assets` is an
  # optional block on datadog_monitor, so with none declared here Terraform would
  # send an empty list and DELETE those links — a plan on 2026-08-18 showed exactly
  # that (assets: [{runbook /notebook/20715...}] -> []) across all five monitors.
  # Runbooks are real operator work and are not modelled in this repo, so they are
  # ignored rather than clobbered.
  lifecycle {
    ignore_changes = [assets]
  }
}
