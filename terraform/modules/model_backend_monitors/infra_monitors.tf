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

# DocumentDB (Mongo-compatible) reachability — DNS/connection failures.
# console-api's health check logs "MongoDB health check failed: <docdb endpoint>
# ... [Errno -3] Try again" when it can't RESOLVE the DocumentDB cluster endpoint
# (EAI_AGAIN — temporary DNS failure), or otherwise can't connect within the 20s
# timeout. Baseline is ~0 (2 events over the 7 days to 2026-06-23), and the DB
# itself is healthy (CPU ~14%, cache 100%, connections nominal) — so this is a
# DNS/network-reachability signal (CoreDNS pressure, Route53/DocDB DNS hiccup, or
# a cluster failover), not a database-load problem. Threshold is low because any
# sustained recurrence above the ~0 baseline is worth a look.
resource "datadog_monitor" "docdb_health_check_failing" {
  name = "[${var.tenant}] DocumentDB - health check failing (DNS / reachability)"
  type = "log alert"

  query = "logs(\"env:production service:console-api \\\"MongoDB health check failed\\\"\").index(\"*\").rollup(\"count\").last(\"10m\") > 5"

  message = <<-EOT
    {{#is_alert}}
    console-api's DocumentDB health check is failing — {{value}} failures in the last 10 minutes. The usual cause is the DocumentDB cluster endpoint failing to resolve (`[Errno -3] Try again` / EAI_AGAIN) or not connecting within the 20s timeout.

    The DB itself is typically healthy here, so suspect DNS/network: in-cluster CoreDNS capacity, the Route53 record for the DocDB endpoint, or a cluster failover/maintenance window. Correlate with the DocumentDB widgets on the Service Mesh & Infra Health dashboard (connections / CPU) to rule out a real cluster issue.
    {{/is_alert}}
    {{#is_warning}}
    DocumentDB health check failing intermittently ({{value}} in 10m). Watch for escalation to a sustained outage.
    {{/is_warning}}

    Tenant: ${var.tenant} @ Query: service:console-api "MongoDB health check failed"
    ${var.notification_channel}
  EOT

  monitor_thresholds {
    critical = 5
    warning  = 1
  }

  include_tags    = false
  notify_audit    = false
  on_missing_data = "default"

  tags = concat(local.base_tags, ["layer:documentdb", "signal:dns-reachability"])
}

# Container OOMKilled — crash-loop detection.
# Containerd emits event_type:oom when the kernel's cgroup OOM killer terminates
# a container (exit code 137). Those events don't land in the logs index (so a
# log alert can't see them), but the PROBE FAILURES that immediately follow DO:
# istio's probes log "connection refused" or "connection reset" against the
# dead container. Watching for those gives us a log alert with a proper
# time-series graph AND fires at the same moment. A single probe failure is
# transient; >=2 in 10 minutes means the container is crash-looping.
# Motivated by GSA api crash-looping (51 OOMs/24h, 2026-07-09) with zero
# alerting coverage.
resource "datadog_monitor" "container_oom_kill_loop" {
  name = "[${var.tenant}] Container crash-loop — OOMKilled / probe failing (exit 137)"
  type = "event-v2 alert"

  query = "events(\"source:containerd event_type:oom\").rollup(\"count\").last(\"10m\") >= 2"

  message = <<-EOT
    {{#is_alert}}
    A container is being OOMKilled repeatedly ({{value}} kills in 10 minutes) — it is crash-looping. The kernel's cgroup OOM killer is terminating the process (exit code 137) because it hit its memory limit.

    Check the deployment's memory limit vs actual usage. Common causes:
    - Traffic spike or aggressive client driving concurrent request buffering
    - Memory leak (growing across restarts)
    - Limit set too low for the workload's steady-state

    Look at Containerd events in Datadog (source:containerd event_type:oom) and the Infra Health dashboard "Container OOMKilled" section to identify the affected deployment/pod.
    {{/is_alert}}
    {{#is_warning}}
    Container OOM kills detected ({{value}} in 10m). Not yet a crash-loop but watch for escalation.
    {{/is_warning}}

    Tenant: ${var.tenant} @ Query: containerd OOM events
    ${var.notification_channel}
  EOT

  monitor_thresholds {
    critical = 2
    warning  = 1
  }

  include_tags    = false
  notify_audit    = false
  on_missing_data = "default"

  tags = concat(local.base_tags, ["layer:kubernetes", "signal:oom-kill"])
}

# Deployment availability: a rollout that is stuck, an orphaned deployment that
# never converges, or pods that won't schedule all show up as
# desired-replicas > ready-replicas that STAYS elevated. Kubernetes surfaces
# this as "Deployment does not have minimum availability"; kube-state-metrics
# exposes it as kubernetes_state.deployment.replicas_desired vs .replicas_ready.
# A brief gap during a normal rolling update is expected, so we only alert when
# a deployment is short of its desired replicas for a sustained window (30m).
#
# Motivated by GSA-TTS/usai#896 (2026-07-20): the legacy frontend-apps
# deployment on doc/dot/usda ran a vulnerable image and never converged for a
# full day with ZERO alerting — found only by hand. This is the monitor that
# would have paged on it.
resource "datadog_monitor" "deployment_unavailable" {
  name = "[${var.tenant}] Deployment lacks minimum availability (stuck rollout / not ready)"
  type = "query alert"

  # avg over the window: fires when a deployment is short of desired for the
  # MAJORITY of 30m — catches a flatly-stuck deploy AND a flapping/crash-looping
  # one (min() would let a momentary Ready blip suppress the page), while a brief
  # rolling-update dip averages back below 1 and self-clears. Grouped by
  # cluster+namespace+deployment so multi-cluster orgs don't cross-aggregate and
  # the alert names the offender.
  query = "avg(last_30m):( max:kubernetes_state.deployment.replicas_desired{*} by {kube_cluster_name,kube_namespace,kube_deployment} - max:kubernetes_state.deployment.replicas_ready{*} by {kube_cluster_name,kube_namespace,kube_deployment} ) >= 1"

  message = <<-EOT
    {{#is_alert}}
    Deployment {{kube_deployment.name}} in {{kube_namespace.name}} has been short of its desired replicas for 30+ minutes ({{value}} replica(s) not ready) — "does not have minimum availability".

    This is NOT a normal rolling update (those recover within the window). Likely causes:
    - A stuck/failed rollout (new pods not passing readiness)
    - An orphaned or unmanaged deployment that can no longer schedule (e.g. missing secret, node pressure, superseded by a migration)
    - Image pull / config error on the current tag

    Check `kubectl get deploy -n {{kube_namespace.name}}` and the pod events. If the deployment is legacy/superseded, it should be removed rather than left half-running (see GSA-TTS/usai#896).
    ${var.notification_channel}
    {{/is_alert}}
    {{#is_recovery}}
    Recovered: {{kube_deployment.name}} in {{kube_namespace.name}} is back to full availability.
    ${var.notification_channel}
    {{/is_recovery}}

    Tenant: ${var.tenant} @ Query: kubernetes_state.deployment desired vs ready
  EOT

  monitor_thresholds {
    critical = 1
  }

  # A genuinely stuck deployment persists; re-page at most every 2h rather than
  # flapping. Groups evaluate independently so one bad deploy doesn't mask others.
  renotify_interval = 120

  # on_missing_data "default" = do nothing when the series stops reporting — a
  # deployment that disappears entirely is a different signal, and this avoids a
  # false page on every intentional teardown. (Mutually exclusive with the
  # legacy notify_no_data, so only this one is set.)
  on_missing_data = "default"
  include_tags    = true
  notify_audit    = false

  tags = concat(local.base_tags, ["layer:kubernetes", "signal:deployment-availability"])
}
