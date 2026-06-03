# AWS Bedrock monitors for the USAi platform.
#
# Motivated by the 2026-06-02 GSA incident (~15:45 EDT): model invocation
# latency on claude-sonnet-4-5 and claude-opus-4-5 spiked from an ~8s baseline
# to 88-115s, throughput collapsed, and it presented to users as an outage.
# Notably AWS reported ZERO InvocationThrottles / ClientErrors / ServerErrors —
# it was model-side latency degradation, not rate-limiting. So latency is the
# leading indicator here; throttles are kept as cheap insurance.
#
# Metrics arrive via the Datadog AWS integration (namespace aws.bedrock.*),
# tagged by modelid. Monitors are multi-alert (grouped by modelid) so a single
# degraded model alerts without being diluted by healthy ones.

resource "datadog_monitor" "bedrock_invocation_latency_high" {
  name = "Bedrock - Invocation Latency High (>30s avg, per model)"
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

    Metric: aws.bedrock.invocation_latency by modelid
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

  tags = ["managed-by:terraform", "service:bedrock", "platform:usai"]
}

resource "datadog_monitor" "bedrock_invocation_throttles" {
  name = "Bedrock - Invocation Throttles (rate-limited by AWS)"
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

    Metric: aws.bedrock.invocation_throttles by modelid
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

  tags = ["managed-by:terraform", "service:bedrock", "platform:usai"]
}

resource "datadog_monitor" "bedrock_server_errors" {
  name  = "Bedrock - Server Errors (5xx from model service)"
  type  = "metric alert"
  query = "sum(last_5m):sum:aws.bedrock.invocation_server_errors{*} by {modelid}.as_count() > 5"

  message = <<-EOT
    {{#is_alert}}
    Bedrock model {{modelid.name}} returned {{value}} server errors (5xx) in the last 5 minutes — the model service itself is failing requests. Check AWS Health Dashboard for Bedrock service events in us-east-1.
    {{/is_alert}}

    Metric: aws.bedrock.invocation_server_errors by modelid
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

  tags = ["managed-by:terraform", "service:bedrock", "platform:usai"]
}

resource "datadog_monitor" "bedrock_invocations_drop" {
  name = "Bedrock - Invocation Throughput Collapse (active model went quiet)"
  type = "metric alert"
  # Downstream symptom: when latency saturates the app, invocations crater
  # (the 2026-06-02 drop from ~80 to ~2 per 5m). Detects the collapse for a
  # model that WAS serving traffic. on_missing_data left at default so a model
  # that legitimately stops being used doesn't false-alarm.
  query = "sum(last_15m):sum:aws.bedrock.invocations{*} by {modelid}.as_count() < 3"

  message = <<-EOT
    {{#is_alert}}
    Bedrock model {{modelid.name}} invocation volume has collapsed to {{value}} over the last 15 minutes. If this model was actively serving traffic, throughput has stalled — often the downstream symptom of the latency/saturation failure mode (see bedrock_invocation_latency_high). Correlate with the latency monitor.
    {{/is_alert}}

    Metric: aws.bedrock.invocations by modelid
    ${var.notification_channel}
  EOT

  monitor_thresholds {
    critical = 3
  }

  notify_no_data    = false
  renotify_interval = 60
  notify_audit      = false
  new_group_delay   = 300

  tags = ["managed-by:terraform", "service:bedrock", "platform:usai"]
}
