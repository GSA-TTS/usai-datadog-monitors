# All active Datadog/AWS providers are declared per-tenant in tenants.tf as
# aliased providers (providers cannot use for_each, so each org is explicit).
#
# There is intentionally NO default (un-aliased) `datadog` provider: every
# resource is created through a tenant-aliased provider via a module call.
#
# When aigov's secret is tagged Environment=production and becomes readable,
# re-enable the aigov-only Keycloak monitors + dashboard by:
#   1. renaming monitors.tf.aigov-pending -> monitors.tf and
#      dashboard.tf.aigov-pending -> dashboard.tf
#   2. adding an aigov block to tenants.tf (aws.aigov alias, secret data
#      sources for aigov-shared-dd-api-key / aigov-shared-dd-app-key, and a
#      datadog.aigov provider alias)
#   3. pointing those Keycloak/dashboard resources at provider = datadog.aigov
#   4. importing the existing aigov resources (IDs in README) so TF adopts
#      rather than duplicates them.
