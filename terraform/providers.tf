# All active Datadog/AWS providers are declared per-tenant in tenants.tf as
# aliased providers (providers cannot use for_each, so each org is explicit).
#
# There is intentionally NO default (un-aliased) `datadog` provider: every
# resource is created through a tenant-aliased provider via a module call.
#
# aigov (the shared account) is now wired in tenants.tf like any other org:
# an aws.aigov alias, secret data sources for aigov-shared-dd-api-key /
# aigov-shared-dd-app-key, and a datadog.aigov provider alias. Unlike the
# other tenants it gets NO model_backend_monitors module — only the aigov-only
# Keycloak monitors (monitors.tf) and Keycloak dashboard (dashboard.tf), both
# pointed at provider = datadog.aigov and adopted from the pre-existing
# hand-created resources via `terraform import` (ROADMAP P2, done).
