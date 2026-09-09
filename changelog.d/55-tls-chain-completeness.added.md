Incomplete-certificate-chain detection on the edge TLS synthetics
(`disable_aia_intermediate_fetching`), plus a shared SSL synthetic for
`auth.usai.gov`. Datadog completes a partial chain via AIA by default, so
`ssl_cert` passed against a server sending only its leaf — the 2026-09-09
`auth.usai.gov` defect that broke Okta's Java SCIM connector for FAA while
browsers were unaffected. `auth.usai.gov` also had no certificate check at all:
module cert checks are per-tenant and apex-only, and the shared Keycloak host
belongs to no tenant.
