# Model-backend monitors, applied once per tenant org.
#
# Two failure modes from the 2026-06-02 GSA incident, generalized across tenants:
#   1. AWS Bedrock model-side LATENCY degradation (claude-sonnet-4-5 / opus-4-5
#      went 8s -> 88-115s) with ZERO throttles/errors. Latency is the leading
#      indicator. (metric alerts on aws.bedrock.*)
#   2. Azure OpenAI (GPT) HTTP 429s + chat streams aborted mid-flight, visible
#      ONLY in the api service logs. (log alerts on service:api)
#
# All monitors are tagged tenant:<slug> and prefixed with the tenant in their
# name so an alert in a per-tenant Datadog org is immediately attributable.

locals {
  base_tags = ["managed-by:terraform", "platform:usai", "tenant:${var.tenant}"]
}

# ---------------------------------------------------------------------------
# AWS Bedrock (metric alerts, aws.bedrock.* via the Datadog AWS integration)
# ---------------------------------------------------------------------------

resource "datadog_monitor" "bedrock_invocation_latency_high" {
  name = "[${var.tenant}] Bedrock - Invocation Latency High (>60s avg, per model)"
  type = "metric alert"
  # Avg invocation latency per model over 15m. 60s critical / 40s warning.
  # Refit 2026-07-10 (2nd pass): 45s/10m still flapped on doc/hud opus-4-8.
  # CloudWatch shows that model AVERAGES ~16s but individual reasoning requests
  # run 48-51s, so in a low-volume 10m window a couple of long calls drag the
  # average over 45s and then back — real latency, but the inherent variance of
  # a heavy reasoning model at low volume, not an incident. 60s over a 15m
  # window smooths that: it takes a sustained cluster of slow calls (a true
  # "stuck" state) to hold the 15m average above 60s. Still well under the 88s+
  # user-visible collapse. Recovery hysteresis (50s/30s) prevents re-flap.
  query = "avg(last_15m):avg:aws.bedrock.invocation_latency{*} by {modelid} > ${local.bedrock_latency_crit_ms}"

  message = <<-EOT
    {{#is_alert}}
    Bedrock model {{modelid.name}} average invocation latency has exceeded 60s over the last 15 minutes (current: {{value}} ms).

    This is the signature of the 2026-06-02 incident: requests succeed but very slowly, saturating app concurrency and collapsing throughput — with NO throttling reported by AWS. Likely a Bedrock model-serving slowdown. Check the model's region capacity and consider failover/load-shedding.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_warning}}
    Bedrock model {{modelid.name}} average invocation latency is elevated (>40s over 15m, current {{value}} ms). Watch for further degradation. (No page — visible on the Model Backend dashboard.)
    {{/is_warning}}
    {{#is_alert_recovery}}
    Recovered: Bedrock model {{modelid.name}} invocation latency back below threshold (current {{value}} ms).
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Metric: aws.bedrock.invocation_latency by modelid
  EOT

  monitor_thresholds {
    critical          = local.bedrock_latency_crit_ms
    warning           = local.bedrock_latency_warn_ms
    critical_recovery = local.bedrock_latency_crit_recovery_ms
    warning_recovery  = local.bedrock_latency_warn_recovery_ms
  }

  notify_no_data    = false
  renotify_interval = 60
  notify_audit      = false
  new_group_delay   = 300

  tags = concat(local.base_tags, ["service:bedrock"])
}

resource "datadog_monitor" "bedrock_invocation_throttles" {
  name = "[${var.tenant}] Bedrock - Invocation Throttles (rate-limited by AWS)"
  type = "metric alert"
  # Any sustained throttling means we've hit a Bedrock quota. Did NOT fire in
  # the 2026-06-02 incident (zero throttles), but cheap insurance for the
  # genuinely-rate-limited case and disambiguates "slow" from "throttled".
  query = "sum(last_5m):sum:aws.bedrock.invocation_throttles{*} by {modelid}.as_count() > 5"

  message = <<-EOT
    {{#is_alert}}
    Bedrock model {{modelid.name}} is being THROTTLED by AWS — {{value}} InvocationThrottles in the last 5 minutes.

    This is a quota/rate-limit problem (distinct from latency degradation). Requests are being rejected. Review the model's TPM/RPM quota usage and request a service quota increase or shed load.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: Bedrock model {{modelid.name}} throttling has cleared.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Metric: aws.bedrock.invocation_throttles by modelid
  EOT

  monitor_thresholds {
    critical = 5
  }

  notify_no_data    = false
  renotify_interval = 60
  notify_audit      = false
  new_group_delay   = 300

  tags = concat(local.base_tags, ["service:bedrock"])
}

resource "datadog_monitor" "bedrock_server_errors" {
  name = "[${var.tenant}] Bedrock - Server Error Rate High (5xx % per model)"
  type = "metric alert"
  # Error RATE, not raw count. Refit 2026-07-09: the old "5 errors in 5m"
  # absolute-count rule flapped constantly and paged on transient low-volume
  # blips — e.g. GSA sonnet-4-6 at 0.6% (26 err / 4173 inv) tripped the same
  # as opus-4-8 at a genuine 5.8% (94 err / 1613 inv). AWS Bedrock 5xx are
  # frequently brief, self-recovering, server-side events; a rate over a 15m
  # window is stable and tells a real degradation from noise.
  #
  # >10% crit over 15m fires on a sustained real problem (opus's 5.8% would
  # NOT page — intentional; that was a transient blip, not an outage). Recovery
  # at 3% gives hysteresis so it won't re-trigger while the rate hovers.
  # Low-volume caveat: over 15m these production chat models see hundreds+ of
  # invocations, so the ratio is well-conditioned; a near-idle model could in
  # principle spike the % on a couple of errors, but new_group_delay + the 15m
  # window make that rare and short-lived.
  query = "sum(last_15m):( sum:aws.bedrock.invocation_server_errors{*} by {modelid}.as_count() / sum:aws.bedrock.invocations{*} by {modelid}.as_count() ) * 100 > 10"

  message = <<-EOT
    {{#is_alert}}
    Bedrock model {{modelid.name}} is failing {{value}}% of requests with 5xx server errors over the last 15 minutes — the model service itself is failing a sustained share of requests, not just a transient blip. Check the AWS Health Dashboard for Bedrock service events in us-east-1 and consider failover.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_alert_recovery}}
    Recovered: Bedrock model {{modelid.name}} 5xx error rate back below threshold (current {{value}}%).
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Metric: aws.bedrock.invocation_server_errors / invocations by modelid
  EOT

  monitor_thresholds {
    critical          = 10
    critical_recovery = 3
  }

  notify_no_data    = false
  renotify_interval = 60
  notify_audit      = false
  new_group_delay   = 300

  tags = concat(local.base_tags, ["service:bedrock"])
}

# NOTE: a "throughput collapse" monitor (bedrock_invocations_drop) was removed
# 2026-06-23. Neither a static threshold nor a per-model anomaly alert worked
# across tenants whose Bedrock traffic spans ~50k/hr (embeddings) down to ~2/hr,
# intermittent chat models. The anomaly version wedged in Alert on a sparse model
# (ftc opus-4-8) that stopped emitting entirely, so the recovery window never
# evaluated and renotify re-paged hourly. The signal is redundant with
# bedrock_invocation_latency_high, which catches the same saturation failure
# upstream and is volume-independent. See RETRO.md v0.1.0 finding and GitHub issue.

# ---------------------------------------------------------------------------
# Azure OpenAI (log alerts on service:api — signal lives only in app logs)
# ---------------------------------------------------------------------------
# ⚠️ BOTH MONITORS BELOW ARE CURRENTLY BLIND — KNOWN BUG, FIX PENDING A DECISION
# Found 2026-09-01 while investigating why the dashboard's two Azure widgets were
# rendering empty (fixed in dashboard.tf). The widgets and these monitors share the
# same two queries, and both queries match NOTHING:
#
#   service:api env:production "Too Many Requests"          -> 0 events / 30d
#   service:api env:production "Stream aborted mid-flight"  -> 0 events / 30d
#
# Because these are log alerts with on_missing_data = "default" (no data =>
# not breaching), they have been sitting in OK the whole time. Green, and watching
# nothing. This is exactly the silent-monitor trap cert_monitors.tf documents for
# `synthetics.ssl.days_left`: a monitor that LOOKS like it works is worse than an
# acknowledged gap. Azure HAS been throttling throughout — 4509 events in gsa over
# 7 days — and neither of these fired once.
#
# Two faults, same as the widgets: the service scope is wrong (the signal is split
# across `api` AND `api-beta`; 14d in gsa = api 2801 + api-beta 2609) and the phrase
# is wrong (Azure logs "...have exceeded rate limit", not "Too Many Requests",
# which in these orgs only appears in cloudtrail). "Stream aborted mid-flight" has
# no live equivalent at all.
#
# BOTH QUERIES ARE NOW FIXED. The two monitors took different treatments because
# their signals behave completely differently — see each resource below:
#
#   * azure_openai_throttling  — query fixed, but DELIBERATELY HANDLE-LESS for now.
#     Correcting the query while keeping `> 3 in 5m` AND a Slack handle would page
#     ~19x/day per org, ~480/day across 25 orgs. Measured 5m distribution in gsa
#     over 7d: throttling present in 12.1% of windows, median 4, p95 76, p99 206,
#     max 240 — a NORMAL operating condition, not an incident. And no count
#     threshold works fleet-wide: 7d totals gsa 4509, doc 323, ftc 15, dot 5,
#     hud 0 (~900x spread), so quiet-for-gsa is blind-for-dot. That is the
#     CLAUDE.md rates-over-counts case and the PR #42 flood shape. The threshold
#     redesign (ratio vs sustained-duration vs per-tenant variable) is still an
#     open decision, so the monitor evaluates and displays truth without paging.
#
#   * azure_openai_stream_aborted — repointed to the upstream-500 signal, and it
#     KEEPS its handle, because that signal is low-volume and its existing
#     threshold measured out safe (see the resource for the numbers).
# ---------------------------------------------------------------------------

resource "datadog_monitor" "azure_openai_throttling" {
  name = "[${var.tenant}] Azure OpenAI - rate limited by Azure (no page - threshold un-tuned)"
  type = "log alert"

  # Query fixed 2026-09-01. Was `service:api env:production "Too Many Requests"`,
  # which matched ZERO events over 30 days on two counts: the signal is split
  # across `api` AND `api-beta` (14d in gsa: 2801 + 2609), and Azure's wording is
  # "...have exceeded rate limit" — "Too Many Requests" appears only in cloudtrail
  # logs here, which is why a bare search for it looked like it matched something.
  query = "logs(\"service:(api OR api-beta) env:production \\\"exceeded rate limit\\\"\").index(\"*\").rollup(\"count\").last(\"5m\") > 3"

  # ── DELIBERATELY HANDLE-LESS: DO NOT ADD THE HANDLE BACK WITHOUT RETUNING ──
  # `critical = 3 / warning = 1` was calibrated in 2026-06 against a query that
  # matched nothing, so it has never been tested against real data. Now that the
  # query works, the measured 5m distribution in gsa (7d) is: throttling present in
  # 12.1% of windows, median 4, p95 76, p99 206, max 240 — so `> 3` is breached
  # ~19x/day in gsa alone, and Azure rate-limiting is a normal operating condition
  # here rather than an incident.
  #
  # A count threshold also cannot be made to work fleet-wide: 7d totals are gsa
  # 4509, doc 323, ftc 15, dot 5, hud 0 — a ~900x spread — so any value quiet
  # enough for gsa is blind for dot even during a total outage. Retuning needs a
  # DESIGN choice (ratio against total request volume / sustained-duration /
  # per-tenant variable), which is an open decision.
  #
  # Until then this monitor evaluates and shows the truth on its own page and on the
  # Model Backend dashboard, but sends NOTHING. That is a deliberate, documented
  # trade-off and strictly better than the previous state, where it sat green while
  # matching nothing at all (the silent-monitor trap).
  #
  # HONEST CAVEAT, learned from PR #48: handle-less monitors get ignored. The
  # 45-day cert tier was handle-less on the same "it's a ticket, not a page"
  # reasoning and ed/gsa still reached 18 days to expiry unseen. So treat this as a
  # short-lived interim, not a resting state — the thresholds still need doing.
  message = <<-EOT
    {{#is_alert}}
    Azure OpenAI is rate-limiting ${var.tenant} — more than 3 "exceeded rate limit" log lines in the last 5 minutes across the `api` / `api-beta` services.

    **This monitor does not page, and its threshold is NOT calibrated.** Rate limiting is a routine condition here (measured: present in ~12% of 5-minute windows in the busiest org, bursting to 240 events), so a breach of this threshold is not by itself an incident. Use it as a visible signal, not a call to action, until the threshold is redesigned.

    If you are investigating a real user-facing problem, correlate: the upstream-500 monitor (Azure failures actually reaching users), Azure OpenAI quota/TPM usage for this deployment, and whether one high-volume caller is hammering /api/v1/chat/completions. Bedrock has its own separate monitors — this is Azure only.
    {{/is_alert}}
    {{#is_warning}}
    At least one Azure "exceeded rate limit" in the last 5 minutes. Routine; informational only.
    {{/is_warning}}
    {{#is_recovery}}
    Recovered: Azure rate-limiting for ${var.tenant} back below threshold.
    {{/is_recovery}}

    Tenant: ${var.tenant} @ Query: service:(api OR api-beta) "exceeded rate limit"
  EOT

  # Unchanged and knowingly un-tuned — see the note above. Left at the original
  # values rather than invented anew, so the retune starts from a clean baseline
  # instead of a number that looks calibrated but isn't.
  monitor_thresholds {
    critical = 3
    warning  = 1
  }

  include_tags           = false
  notify_audit           = false
  on_missing_data        = "default"
  groupby_simple_monitor = false

  tags = concat(local.base_tags, ["service:api", "provider:azure-openai"])
}

resource "datadog_monitor" "azure_openai_stream_aborted" {
  name = "[${var.tenant}] Azure OpenAI - upstream 500s reaching the app"
  type = "log alert"

  # REPOINTED 2026-09-01. This monitor used to look for "Stream aborted mid-flight"
  # on service:api — the user-visible symptom from the 2026-06-02 incident. That
  # phrase no longer exists anywhere: 0 events over 30 days across ALL services and
  # all of env:production, and the same for "stream aborted", "aborted mid-flight"
  # and bare "abort". Whatever emitted it was removed or reworded, so the monitor
  # had been permanently green with nothing to match (on_missing_data="default").
  #
  # Rather than leave a placeholder implying coverage, it now watches the closest
  # real signal for the same question — "are Azure-side failures reaching users?" —
  # which is upstream 500s relayed to the app, e.g.
  #   500: Internal Server Error | headers: {...'Server': 'envoy'...}
  #
  # The `api OR api-beta` scope is required for the same reason as the throttling
  # monitor: the work is split across both services.
  query = "logs(\"service:(api OR api-beta) env:production \\\"Internal Server Error\\\"\").index(\"*\").rollup(\"count\").last(\"5m\") > 3"

  # ── THIS ONE KEEPS ITS HANDLE: the threshold measured out safe ──────────────
  # Unlike the throttling monitor, this signal is low-volume and well-behaved, so
  # the inherited `> 3 in 5m` is genuinely calibrated rather than inherited-on-faith.
  # Measured over 7d in 5m buckets:
  #   gsa   80 events, non-zero in 48/2016 windows, max 6,  p95 3  -> `>3` fires 2x/7d
  #   usda  16 events, max 4                                       -> `>3` fires 1x/7d
  #   hud    1 event                                               -> never
  #   doc / ftc / dot  zero                                        -> never
  # So ~0.3 pages/day in the busiest org and none in most — a real, actionable rate.
  # There is also no 900x cross-tenant spread here (unlike throttling), so a count
  # threshold is legitimate for this signal.
  message = <<-EOT
    {{#is_alert}}
    More than 3 upstream 500s have reached the ${var.tenant} app in the last 5 minutes (`api` / `api-beta`). Users are seeing failed requests — this is the Azure-side failure signal that actually surfaces to them.

    Triage: check the Azure-rate-limited monitor and the Model Backend dashboard — sustained throttling often precedes 500s, though rate limiting alone is routine here and does not imply this. Then check Azure OpenAI deployment health/quota for this tenant. Bedrock has separate monitors; this is Azure only.

    NOTE this monitor previously watched for "Stream aborted mid-flight", which no longer exists in the logs at all (0 events / 30d, all services). If you are looking for the classic mid-stream cutoff symptom, it is no longer directly instrumented — this 500 count is the nearest available proxy.
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_warning}}
    At least one upstream 500 reached the app in the last 5 minutes. Below the paging threshold — handle-less by design.
    {{/is_warning}}
    {{#is_alert_recovery}}
    Recovered: upstream 500s to the ${var.tenant} app back below threshold.
    ${var.notification_channel}
    {{/is_alert_recovery}}

    Tenant: ${var.tenant} @ Query: service:(api OR api-beta) "Internal Server Error"
  EOT

  monitor_thresholds {
    critical = 3
    warning  = 1
  }

  include_tags           = false
  notify_audit           = false
  on_missing_data        = "default"
  groupby_simple_monitor = false

  tags = concat(local.base_tags, ["service:api", "provider:azure-openai"])
}
