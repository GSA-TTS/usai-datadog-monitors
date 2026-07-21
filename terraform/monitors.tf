resource "datadog_monitor" "keycloak_login_failures_spike" {
  provider = datadog.aigov
  name     = "Keycloak - Login Failures Spike (>20 in 5 min)"
  type     = "log alert"
  query    = "logs(\"service:keycloak \\\"org.keycloak.events\\\" type=LOGIN_ERROR env:production\").index(\"*\").rollup(\"count\").last(\"5m\") > 20"
  message  = <<-EOT
    Keycloak login failures have exceeded the threshold of 20 in the last 5 minutes. This may indicate a brute-force attack or credential stuffing attempt. Please investigate immediately.

    Environment: production @ Query: service:keycloak type=LOGIN_ERROR
    ${var.notification_channel}
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
}

resource "datadog_monitor" "keycloak_login_success_rate_drop" {
  provider = datadog.aigov
  name     = "Keycloak - Login Success Rate Drop (High Error Volume)"
  type     = "log alert"
  query    = "logs(\"service:keycloak \\\"org.keycloak.events\\\" type=LOGIN_ERROR env:production\").index(\"*\").rollup(\"count\").last(\"5m\") > 40"
  message  = <<-EOT
    Keycloak login error count has exceeded 40 in the last 5 minutes, indicating the login success rate may have dropped below 95%. This could signal an authentication service issue or an ongoing attack. Please investigate immediately. Environment: production
    ${var.notification_channel}
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
}

resource "datadog_monitor" "keycloak_invalid_credentials_spike" {
  provider = datadog.aigov
  name     = "Keycloak - Invalid Credentials Error Spike (>10 in 5 min)"
  type     = "log alert"
  query    = "logs(\"service:keycloak \\\"org.keycloak.events\\\" type=LOGIN_ERROR error=invalid_user_credentials env:production\").index(\"*\").rollup(\"count\").last(\"5m\") > 10"
  message  = <<-EOT
    Keycloak invalid_user_credentials errors have exceeded 10 in the last 5 minutes. This may indicate credential stuffing, a brute force attack, or a misconfigured client application. Please review the source IPs and affected users. Environment: production
    ${var.notification_channel}
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
}

resource "datadog_monitor" "keycloak_active_users_drop" {
  provider = datadog.aigov
  name     = "Keycloak - Active Users Drop (Login Activity Below Normal)"
  type     = "log alert"
  query    = "logs(\"service:keycloak \\\"org.keycloak.events\\\" type=LOGIN env:production\").index(\"*\").rollup(\"count\").last(\"30m\") < 2"
  message  = <<-EOT
    Keycloak login activity has dropped below 2 events in the last 30 minutes. This may indicate an authentication service outage or connectivity issue. Please check the Keycloak service health immediately. Environment: production
    ${var.notification_channel}
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
}

resource "datadog_monitor" "keycloak_top_failing_clients_spike" {
  provider = datadog.aigov
  name     = "Keycloak - Top Failing Clients Spike (>15 errors in 5 min)"
  type     = "log alert"
  query    = "logs(\"service:keycloak \\\"org.keycloak.events\\\" type=LOGIN_ERROR env:production\").index(\"*\").rollup(\"count\").last(\"5m\") > 15"
  message  = <<-EOT
    Keycloak login errors have exceeded 15 in the last 5 minutes across client applications. Based on the dashboard, high-volume clients like usai-chat and usai-console may be affected. Please check the Top Failing Clients widget in the Keycloak dashboard and review client configurations. Environment: production
    ${var.notification_channel}
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
}
