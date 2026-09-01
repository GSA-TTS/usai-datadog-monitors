resource "datadog_rum_application" "tenant_rum" {
  name = "usai-${var.tenant}"
  type = "browser"
}
