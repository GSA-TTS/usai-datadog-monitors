resource "datadog_dashboard_json" "keycloak" {
  provider  = datadog.aigov
  dashboard = file("${path.module}/../dashboards/aigov/keycloak-full.json")
}
