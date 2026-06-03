# Azure OpenAI (GPT) monitors for the USAi platform.
#
# Motivated by the 2026-06-02 GSA incident. The user-facing failure was NOT on
# the AWS Bedrock side (see bedrock_monitors.tf — those models were slow, not
# throttled). It was Azure OpenAI returning HTTP 429 "Too Many Requests" and the
# api service aborting GPT streams mid-flight. 19 such events fired between
# 15:38 and 18:43 EDT, peaking 16:11–16:30 (~9 in 19 min). This signal lives
# ONLY in the application logs (service:api) — no AWS/Bedrock metric shows it —
# which is exactly why the two concurrent failure modes were hard to correlate.
#
# These are log alerts (same mechanism as the Keycloak monitors), not metric
# alerts, because the 429s surface as a log line emitted by the api service.

resource "datadog_monitor" "azure_openai_throttling" {
  name = "Azure OpenAI - Too Many Requests / 429 throttling (api service)"
  type = "log alert"
  # Count of "Too Many Requests" log lines from the api service over 5m.
  # During the 2026-06-02 incident the peak was ~9 in 19 min (~2-3 per 5m),
  # so >3 critical fires at the start of the peak cluster; >1 warning catches
  # the early signal (the first 429 hit at 15:38, ~30 min before the peak).
  query = "logs(\"service:api env:production \\\"Too Many Requests\\\"\").index(\"*\").rollup(\"count\").last(\"5m\") > 3"

  message = <<-EOT
    {{#is_alert}}
    The USAi api service is logging "Too Many Requests" (HTTP 429) — more than 3 in the last 5 minutes. This is the signature of the 2026-06-02 incident: Azure OpenAI (GPT models) is rate-limiting us and chat streams are being aborted mid-flight.

    This is distinct from AWS Bedrock — Bedrock throttling/latency has its own monitors. Check: Azure OpenAI quota/TPM usage for the GSA deployment, any single high-volume caller (e.g. API clients hammering /api/v1/chat/completions), and whether to request an Azure quota increase or shed load.
    {{/is_alert}}
    {{#is_warning}}
    The USAi api service has logged at least one "Too Many Requests" (429) in the last 5 minutes. Azure OpenAI may be starting to throttle — watch for escalation.
    {{/is_warning}}

    Environment: production @ Query: service:api "Too Many Requests"
    ${var.notification_channel}
  EOT

  monitor_thresholds {
    critical = 3
    warning  = 1
  }

  include_tags           = false
  notify_audit           = false
  on_missing_data        = "default"
  new_group_delay        = 300
  groupby_simple_monitor = false

  tags = ["managed-by:terraform", "service:api", "provider:azure-openai", "platform:usai"]
}

resource "datadog_monitor" "azure_openai_stream_aborted" {
  name = "Azure OpenAI - Chat streams aborted mid-flight"
  type = "log alert"
  # The user-visible symptom: a streaming GPT response cut off partway. In the
  # incident these accompanied the 429s ("Stream aborted mid-flight for model").
  # Separate from the 429 count so we catch aborts even if their root cause
  # shifts (timeout, upstream reset) rather than only rate-limiting.
  query = "logs(\"service:api env:production \\\"Stream aborted mid-flight\\\"\").index(\"*\").rollup(\"count\").last(\"5m\") > 3"

  message = <<-EOT
    {{#is_alert}}
    The USAi api service has aborted more than 3 model response streams mid-flight in the last 5 minutes. Users are seeing chat responses cut off partway. In the 2026-06-02 incident this was driven by Azure OpenAI 429s (see the azure_openai_throttling monitor) — correlate the two. If 429s are NOT also firing, suspect upstream timeouts or connection resets instead.
    {{/is_alert}}
    {{#is_warning}}
    At least one model response stream was aborted mid-flight in the last 5 minutes. Watch for escalation.
    {{/is_warning}}

    Environment: production @ Query: service:api "Stream aborted mid-flight"
    ${var.notification_channel}
  EOT

  monitor_thresholds {
    critical = 3
    warning  = 1
  }

  include_tags           = false
  notify_audit           = false
  on_missing_data        = "default"
  new_group_delay        = 300
  groupby_simple_monitor = false

  tags = ["managed-by:terraform", "service:api", "provider:azure-openai", "platform:usai"]
}
