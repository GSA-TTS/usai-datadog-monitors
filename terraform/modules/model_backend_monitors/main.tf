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
  name = "[${var.tenant}] Bedrock - Invocation Latency High (>30s avg, per model)"
  type = "metric alert"
  # Avg invocation latency per model over 10m. 30s critical / 20s warning —
  # well above the ~8s baseline but ~3x earlier than the 88s+ user-visible
  # collapse, giving lead time to react.
  query = "avg(last_10m):avg:aws.bedrock.invocation_latency{*} by {modelid} > 30000"

  message = <<-EOT
    {{#is_alert}}
    Bedrock model {{modelid.name}} average invocation latency has exceeded 30s over the last 10 minutes (current: {{value}} ms).

    This is the signature of the 2026-06-02 incident: requests succeed but very slowly, saturating app concurrency and collapsing throughput — with NO throttling reported by AWS. Likely a Bedrock model-serving slowdown. Check the model's region capacity and consider failover/load-shedding.
    {{/is_alert}}
    {{#is_warning}}
    Bedrock model {{modelid.name}} average invocation latency is elevated (>20s over 10m, current {{value}} ms). Watch for further degradation.
    {{/is_warning}}

    Tenant: ${var.tenant} @ Metric: aws.bedrock.invocation_latency by modelid
    ${var.notification_channel}
  EOT

  monitor_thresholds {
    critical = 30000
    warning  = 20000
  }

  notify_no_data    = false
  renotify_interval = 30
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
    {{/is_alert}}

    Tenant: ${var.tenant} @ Metric: aws.bedrock.invocation_throttles by modelid
    ${var.notification_channel}
  EOT

  monitor_thresholds {
    critical = 5
    warning  = 1
  }

  notify_no_data    = false
  renotify_interval = 30
  notify_audit      = false
  new_group_delay   = 300

  tags = concat(local.base_tags, ["service:bedrock"])
}

resource "datadog_monitor" "bedrock_server_errors" {
  name  = "[${var.tenant}] Bedrock - Server Errors (5xx from model service)"
  type  = "metric alert"
  query = "sum(last_5m):sum:aws.bedrock.invocation_server_errors{*} by {modelid}.as_count() > 5"

  message = <<-EOT
    {{#is_alert}}
    Bedrock model {{modelid.name}} returned {{value}} server errors (5xx) in the last 5 minutes — the model service itself is failing requests. Check AWS Health Dashboard for Bedrock service events in us-east-1.
    {{/is_alert}}

    Tenant: ${var.tenant} @ Metric: aws.bedrock.invocation_server_errors by modelid
    ${var.notification_channel}
  EOT

  monitor_thresholds {
    critical = 5
    warning  = 1
  }

  notify_no_data    = false
  renotify_interval = 30
  notify_audit      = false
  new_group_delay   = 300

  tags = concat(local.base_tags, ["service:bedrock"])
}

resource "datadog_monitor" "bedrock_invocations_drop" {
  name = "[${var.tenant}] Bedrock - Invocation Throughput Collapse (active model went quiet)"
  type = "query alert"
  # Downstream symptom: when latency saturates the app, invocations crater (the
  # 2026-06-02 drop from ~80 to ~2 per 5m). A STATIC threshold can't express
  # "collapse" across tenants whose models range from ~50k/hr (embeddings) down
  # to ~2/hr (sporadic chat) — "< 3 in 15m" is normal for a low-traffic model
  # and false-fired immediately. So this is an ANOMALY alert per model: it fires
  # only when a model drops below ITS OWN learned baseline.
  #
  #  - anomalies(..., 'agile', 3): agile adapts to level shifts/seasonality;
  #    bound = 3 std devs.
  #  - direction='below': only a DROP is interesting, never a spike.
  #  - count_default_zero='true': quiet gaps count as zero against the baseline
  #    (so a genuine stall on a previously-busy model registers).
  # A model that is consistently low-traffic has a low baseline, so staying low
  # is NOT anomalous and won't page — which is exactly the false positive we hit.
  query = "avg(last_15m):anomalies(sum:aws.bedrock.invocations{*} by {modelid}.as_count(), 'agile', 3, direction='below', interval=60, alert_window='last_15m', count_default_zero='true', seasonality='hourly') >= 1"

  message = <<-EOT
    {{#is_alert}}
    Bedrock model {{modelid.name}} invocation volume has dropped well below its normal baseline over the last 15 minutes. If this model was actively serving traffic, throughput has stalled — often the downstream symptom of the latency/saturation failure mode (see the latency monitor). Correlate with the latency monitor.
    {{/is_alert}}

    Tenant: ${var.tenant} @ Metric: aws.bedrock.invocations by modelid (anomaly, direction=below)
    ${var.notification_channel}
  EOT

  # Anomaly monitors threshold on the FRACTION of the alert window that is
  # anomalous (1.0 = the whole window). Recovery when no longer anomalous.
  monitor_thresholds {
    critical = 1.0
  }

  monitor_threshold_windows {
    trigger_window  = "last_15m"
    recovery_window = "last_15m"
  }

  notify_no_data    = false
  renotify_interval = 60
  notify_audit      = false
  new_group_delay   = 300

  tags = concat(local.base_tags, ["service:bedrock"])
}

# ---------------------------------------------------------------------------
# Azure OpenAI (log alerts on service:api — signal lives only in app logs)
# ---------------------------------------------------------------------------

resource "datadog_monitor" "azure_openai_throttling" {
  name = "[${var.tenant}] Azure OpenAI - Too Many Requests / 429 throttling (api service)"
  type = "log alert"
  # Count of "Too Many Requests" log lines from the api service over 5m.
  # During the 2026-06-02 incident the peak was ~9 in 19 min (~2-3 per 5m),
  # so >3 critical fires at the start of the peak cluster; >1 warning catches
  # the early signal (the first 429 hit at 15:38, ~30 min before the peak).
  query = "logs(\"service:api env:production \\\"Too Many Requests\\\"\").index(\"*\").rollup(\"count\").last(\"5m\") > 3"

  message = <<-EOT
    {{#is_alert}}
    The USAi api service is logging "Too Many Requests" (HTTP 429) — more than 3 in the last 5 minutes. This is the signature of the 2026-06-02 incident: Azure OpenAI (GPT models) is rate-limiting us and chat streams are being aborted mid-flight.

    This is distinct from AWS Bedrock — Bedrock throttling/latency has its own monitors. Check: Azure OpenAI quota/TPM usage for this deployment, any single high-volume caller (e.g. API clients hammering /api/v1/chat/completions), and whether to request an Azure quota increase or shed load.
    {{/is_alert}}
    {{#is_warning}}
    The USAi api service has logged at least one "Too Many Requests" (429) in the last 5 minutes. Azure OpenAI may be starting to throttle — watch for escalation.
    {{/is_warning}}

    Tenant: ${var.tenant} @ Query: service:api "Too Many Requests"
    ${var.notification_channel}
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

resource "datadog_monitor" "azure_openai_stream_aborted" {
  name = "[${var.tenant}] Azure OpenAI - Chat streams aborted mid-flight"
  type = "log alert"
  # The user-visible symptom: a streaming GPT response cut off partway. In the
  # incident these accompanied the 429s ("Stream aborted mid-flight for model").
  # Separate from the 429 count so we catch aborts even if their root cause
  # shifts (timeout, upstream reset) rather than only rate-limiting.
  query = "logs(\"service:api env:production \\\"Stream aborted mid-flight\\\"\").index(\"*\").rollup(\"count\").last(\"5m\") > 3"

  message = <<-EOT
    {{#is_alert}}
    The USAi api service has aborted more than 3 model response streams mid-flight in the last 5 minutes. Users are seeing chat responses cut off partway. In the 2026-06-02 incident this was driven by Azure OpenAI 429s (see the throttling monitor) — correlate the two. If 429s are NOT also firing, suspect upstream timeouts or connection resets instead.
    {{/is_alert}}
    {{#is_warning}}
    At least one model response stream was aborted mid-flight in the last 5 minutes. Watch for escalation.
    {{/is_warning}}

    Tenant: ${var.tenant} @ Query: service:api "Stream aborted mid-flight"
    ${var.notification_channel}
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
