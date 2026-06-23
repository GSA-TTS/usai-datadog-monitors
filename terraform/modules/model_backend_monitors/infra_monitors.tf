# Infrastructure-health log alerts for the USAi service mesh.
#
# Motivated by a 2026-06-23 ftc incident: a 2-day error review found 90,194
# "errors" that were almost entirely INFRASTRUCTURE noise, not app bugs. The
# dominant signal was a real, bounded event — istio's Citadel/istiod certificate
# authority returning `rpc error: code = Unavailable` on workload mTLS cert
# signing (~08:00–14:00Z, peaking ~5,700/hr). That cert-signing outage is the
# likely root cause of the same-morning multi-tenant synthetics health-check
# failures (chat.<tenant>.usai.gov/health). Nothing alerted on it proactively.
#
# These log alerts watch the mesh-infrastructure signals the apps emit (via the
# istio/envoy sidecars and the dd-trace agent), so the next control-plane event
# pages instead of being discovered after the fact.
#
# Instantiated once per tenant via the enclosing module.

# istio mTLS certificate signing failing — the 2026-06-23 incident signature.
# When istiod/Citadel can't sign workload certs, sidecar mTLS breaks and health
# probes fail mesh-wide. Threshold sized off the incident: baseline is ~0/5m, the
# incident ran ~475/5m, so >50 in 5m is a clear, early signal well below peak.
resource "datadog_monitor" "istio_cert_signing_failures" {
  name = "[${var.tenant}] istio - mTLS certificate signing failing (control-plane)"
  type = "log alert"

  query = "logs(\"env:production (\\\"failed to sign CSR\\\" OR \\\"failed to sign\\\") (citadelclient OR cache)\").index(\"*\").rollup(\"count\").last(\"5m\") > 50"

  message = <<-EOT
    {{#is_alert}}
    istio is failing to sign workload mTLS certificates ({{value}} failures in the last 5 minutes) — `rpc error: code = Unavailable` from Citadel/istiod. When cert signing is down, sidecar mTLS breaks across the mesh and service health checks start failing (this was the root cause of the 2026-06-23 multi-tenant synthetics outages).

    Check istiod/Citadel health in this tenant's cluster. This is service-mesh infrastructure (FCS-managed), not a USAi application bug.
    {{/is_alert}}
    {{#is_warning}}
    Elevated istio cert-signing failures ({{value}} in 5m). Watch for escalation / mesh degradation.
    {{/is_warning}}

    Tenant: ${var.tenant} @ Query: "failed to sign" + citadel/cache
    ${var.notification_channel}
  EOT

  monitor_thresholds {
    critical = 50
    warning  = 10
  }

  include_tags    = false
  notify_audit    = false
  on_missing_data = "default"

  tags = concat(local.base_tags, ["layer:istio", "signal:mtls"])
}

# dd-trace / profiler agent unable to ship telemetry to the Datadog intake.
# Surfaced on embedding-proxy ("failed to send ... traces to intake",
# "ddog_prof_Exporter_send failed", "Failed to send Instrumentation Telemetry").
# Means observability data is being DROPPED — gaps in APM/traces for that service.
resource "datadog_monitor" "dd_agent_telemetry_send_failures" {
  name = "[${var.tenant}] Datadog agent - telemetry/trace send failing (observability gap)"
  type = "log alert"

  query = "logs(\"env:production service:(chat OR api OR console-api OR console-pipeline-api OR pipelines OR embedding-proxy) (\\\"dropping\\\" \\\"traces to intake\\\" OR ddog_prof_Exporter_send OR \\\"Instrumentation Telemetry\\\")\").index(\"*\").rollup(\"count\").last(\"10m\") > 100"

  message = <<-EOT
    {{#is_alert}}
    The Datadog tracer/profiler agent is failing to ship telemetry to the intake ({{value}} send-failures in 10 minutes) — dropped traces / `ddog_prof_Exporter_send failed` / failed instrumentation telemetry. APM and profiling data for the affected service (most often embedding-proxy) is being LOST, so traces will have gaps.

    Check the dd-trace agent connectivity / intake endpoint reachability from the affected pods. This is an observability-pipeline problem, not a user-facing app error.
    {{/is_alert}}

    Tenant: ${var.tenant} @ Query: dd-agent telemetry/trace send failures
    ${var.notification_channel}
  EOT

  monitor_thresholds {
    critical = 100
  }

  include_tags    = false
  notify_audit    = false
  on_missing_data = "default"

  tags = concat(local.base_tags, ["layer:datadog-agent", "signal:telemetry-drop"])
}
