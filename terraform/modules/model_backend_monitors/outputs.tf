output "rum_application_id" {
  description = "Datadog RUM application ID for this tenant."
  value       = datadog_rum_application.tenant_rum.id
}

output "rum_client_token" {
  description = "Datadog RUM client token for this tenant."
  value       = datadog_rum_application.tenant_rum.client_token
}
