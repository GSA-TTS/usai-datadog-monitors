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

# ---------------------------------------------------------------------------
# SCIM provisioning failure (aigov — the shared Keycloak all tenants sync into)
# ---------------------------------------------------------------------------
# Added 2026-09-09 after ED reported users could not access USAi. Every
# GET /realms/ed/scim/v2/Users from Entra was returning 401, and it had been doing
# so since 2026-08-25 with NOTHING alerting. Keycloak was healthy the whole time: a
# freshly minted client-credentials token returns 200 and a valid SCIM ListResponse.
# The failure was a stale IdP credential and it was invisible for two weeks.
#
# WHY NOTHING CAUGHT IT: these are istio-ingressgateway ACCESS logs, not
# service:keycloak events. They carry no parsed attributes (@http.status_code
# returns nothing) and — critically — their level is `info`, not `error`, so no
# error-severity filter or existing monitor could ever have surfaced them.
#
# ── THRESHOLD IS `> 0`, WHICH IS DELIBERATE AND MEASURED ────────────────────
# This breaks the repo's usual prefer-rates-over-counts rule, on purpose. A
# correctly configured IdP NEVER receives a 401 here, so zero is the only correct
# steady state and there is no baseline to express as a rate.
#
# It is also what the data requires. 401s per HOUR over 30 days, real IdP traffic:
#   only 12 non-empty hours out of 720, distributed
#   {1 -> 6 hours, 2 -> 3 hours, 3 -> 1, 7 -> 1, 20 -> 1}
# So the majority of broken hours contain just ONE or TWO 401s. A `> 2 in 1h` rule
# would have fired in 3 of those 12 hours and missed 75% of the outage. Anything
# above zero is too high for a signal this sparse.
#
# Volume makes `> 0` safe rather than noisy: 42 real-IdP 401s in 30 days total, so
# this physically cannot flood — the opposite failure mode from PR #42's ~200-alert
# count monitor.
#
# ── WINDOW IS 1d, NOT 1h, TO STOP FLAPPING ─────────────────────────────────
# IdP retries are sparse and irregular (ED: 14:46, 14:51, 15:00, 15:14, 15:34,
# 16:54 — then nothing for hours). With a 1h window the monitor would recover
# between retries and re-alert on the next one, and each fresh Alert transition
# pages regardless of renotify_interval. A 1d window holds one Alert across the
# whole broken day. The cost is that recovery lags up to 24h after a real fix —
# acceptable, because you verify a provisioning fix from the IdP's Test Connection
# and the dashboard, not by waiting for this monitor to clear.
#
# ── NO PER-REALM MONITOR, AND NO "SCIM WENT QUIET" MONITOR ─────────────────
# Per-realm is not expressible: the realm lives in raw URL text with no facet, so
# grouping is impossible and the alternative is 8 hardcoded monitors — fan-out for
# no gain, and this session already paid for that twice (#49, #50). The message
# points at the dashboard's per-realm widget instead, which is one click.
#
# A "SCIM has stopped being called" monitor was considered and rejected: traffic is
# genuinely intermittent (12 active hours in 30 days), so absence of requests is
# normal and such a monitor would false-page continuously.
# ── ONE MONITOR PER REALM, so the alert names the tenant ────────────────────
# Originally a single aggregate monitor. Changed 2026-09-09 because the resulting
# page read "SCIM provisioning failing — IdP token rejected (401)" with no
# indication of WHICH tenant, which makes it near-useless to whoever is on call:
# every SCIM realm belongs to a different agency whose IdP admins have to make the
# fix, so the tenant is the single most important field in the alert.
#
# WHY for_each RATHER THAN group_by: the realm lives in raw URL text in an
# istio-ingressgateway access log. There is no facet for it — group_by on @realm,
# @http.url_details.path and @http.status_code all return nothing (verified
# 2026-09-09), so a multi-alert monitor cannot be built. Only `host`, `service` and
# `kube_namespace` are groupable and all three are uniform across these logs.
#
# The fan-out is acceptable here, unlike #49/#50: 8 monitors on a signal totalling
# 42 real-IdP 401s in 30 days, each re-notifying daily. A fleet-wide SCIM break
# pages 8 times, which is arguably correct since 8 different IdP owners must act.
# It also buys per-tenant muting and routing, which an aggregate monitor cannot do.
#
# BETTER LONG-TERM FIX, deliberately not done here: add a log pipeline that Groks
# these access logs into real `realm` and `status_code` attributes. That would
# collapse this back to ONE multi-alert monitor with {{realm.name}} in the message,
# and would also replace the fragile `401` TEXT match with @status_code:401. It is
# not done in this change because a Grok parser cannot be verified before shipping
# without a pipeline test API, and an incorrect one silently stops parsing. The org
# already runs 6 pipelines (including two for Keycloak) so the pattern exists.
locals {
  # Realms with a scim-client in Keycloak, verified against the admin API
  # 2026-09-09. doc/sss/ncua have never sent a SCIM request; their monitors sit in
  # OK via on_missing_data and cost nothing, but mean a newly-wired IdP is covered
  # from its first request rather than after the next outage.
  scim_realms = ["ed", "ntsb", "faa", "doj", "ncua", "doc", "sss", "opm"]
}

resource "datadog_monitor" "scim_provisioning_failing" {
  for_each = toset(local.scim_realms)

  provider = datadog.aigov
  name     = "SCIM provisioning failing — ${each.value} — IdP token rejected (401)"
  type     = "log alert"

  # `-curl` excludes hand-run probing so this reflects real IdP traffic only. It is
  # load-bearing, not tidiness: without it the same data reads 401:54 / 200:20 and
  # looks partly healthy, when every one of those 200s is manual curl (setup testing
  # on 08-25 plus this investigation). Real-IdP successes over 30 days: zero.
  query = "logs(\"\\\"/realms/${each.value}/scim/v2\\\" 401 -curl\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"

  message = <<-EOT
    {{#is_alert}}
    SCIM user provisioning for **${each.value}** is being REJECTED by the shared Keycloak — {{value}} request(s) returned 401 in the last 24h. **${each.value} cannot provision or deprovision users**, so new staff get no access and departed staff keep theirs.

    **Almost always the same cause:** ${each.value}'s IdP is configured with a static *Bearer Token*. Keycloak issues those with a 60-minute lifespan and the IdP cannot refresh one, so provisioning works for an hour after setup and then 401s forever. Confirm by minting a token by hand — if a fresh token gets 200 on `/realms/${each.value}/scim/v2/Users`, the server is fine and the IdP credential is the problem.

    **Fix:** switch ${each.value}'s IdP to **OAuth2 Client Credentials Grant** against `https://auth.usai.gov/realms/${each.value}/protocol/openid-connect/token`, client `scim-client`, and leave the **Scope field EMPTY** — Keycloak rejects `read write` with `invalid_scope` (that value is Contrast-specific; those scopes do not exist in these realms).

    Entra and Okta both re-mint their own tokens under this grant, so `access_token_lifespan = 3600` is correct and should NOT be widened. Note tenants differ: faa is on Okta, ed on Entra.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: no SCIM 401s for ${each.value} in the last 24h. Confirm provisioning actually resumed — check for 200s on the Keycloak dashboard's SCIM section, since silence alone also produces this recovery.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Realm: ${each.value} @ Query: "/realms/${each.value}/scim/v2" 401, excluding manual curl
  EOT

  # `> 0` means critical must be 0 to match the query threshold.
  monitor_thresholds {
    critical = 0
  }

  # A rejected IdP credential stays rejected until someone reconfigures the IdP, so
  # re-page daily rather than once — the same reasoning as the cert monitors. Paired
  # with the 1d window this is at most one page per day per affected tenant.
  renotify_interval = 1440

  # No data means no SCIM requests were made at all, which is NORMAL here — traffic
  # is intermittent (12 active hours in 30 days). Must not be treated as breaching.
  on_missing_data        = "default"
  include_tags           = false
  notify_audit           = false
  groupby_simple_monitor = false

  tags = ["managed-by:terraform", "service:keycloak", "tenant:aigov", "signal:scim-provisioning", "scim-realm:${each.value}"]

  # Same reason as the Keycloak monitors above — never clobber UI-attached runbooks.
  lifecycle {
    ignore_changes = [assets]
  }
}
