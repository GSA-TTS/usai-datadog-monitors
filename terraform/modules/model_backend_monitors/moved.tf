# One-time state moves for the enable_alerting count gate. These are module-local,
# so each block applies to every root module instance (dnfsb, gsa, etc.). Keep
# them until all workspaces/orgs have applied the migration.
moved {
  from = datadog_monitor.bedrock_invocation_latency_high
  to   = datadog_monitor.bedrock_invocation_latency_high[0]
}

moved {
  from = datadog_monitor.bedrock_invocation_throttles
  to   = datadog_monitor.bedrock_invocation_throttles[0]
}

moved {
  from = datadog_monitor.bedrock_server_errors
  to   = datadog_monitor.bedrock_server_errors[0]
}

moved {
  from = datadog_monitor.azure_openai_throttling
  to   = datadog_monitor.azure_openai_throttling[0]
}

moved {
  from = datadog_monitor.azure_openai_stream_aborted
  to   = datadog_monitor.azure_openai_stream_aborted[0]
}

moved {
  from = datadog_monitor.istio_cert_signing_failures
  to   = datadog_monitor.istio_cert_signing_failures[0]
}

moved {
  from = datadog_monitor.dd_agent_telemetry_send_failures
  to   = datadog_monitor.dd_agent_telemetry_send_failures[0]
}

moved {
  from = datadog_monitor.docdb_health_check_failing
  to   = datadog_monitor.docdb_health_check_failing[0]
}

moved {
  from = datadog_monitor.container_oom_kill_loop
  to   = datadog_monitor.container_oom_kill_loop[0]
}

moved {
  from = datadog_monitor.deployment_unavailable
  to   = datadog_monitor.deployment_unavailable[0]
}

moved {
  from = datadog_monitor.pod_restart_storm
  to   = datadog_monitor.pod_restart_storm[0]
}

moved {
  from = datadog_monitor.cronjob_failing
  to   = datadog_monitor.cronjob_failing[0]
}

moved {
  from = datadog_monitor.frontend_upstream_api_unreachable
  to   = datadog_monitor.frontend_upstream_api_unreachable[0]
}
