# Platform / FCS infra findings — June 2026 (USAi tenant monitoring)

Surfaced while building the USAi observability monitors & dashboards. Both items
are **service-mesh / infrastructure** concerns (FCS-managed layers), not USAi
application bugs — raising them here for the platform team. Both are now
monitored and visible on the per-tenant **Service Mesh & Infra Health**
dashboard, but the root causes live below the app layer.

Tenant evidence is from **ftc** (`fcs-mcaas-ftc.ddog-gov.com`); the same monitors
are deployed to all 7 enabled tenants (dnfsb, doj, faa, ftc, nrc, ntsb, oge).

---

## 1. istio mTLS certificate-signing outage (2026-06-23)

**What:** istio's Citadel/istiod returned `rpc error: code = Unavailable` on
workload mTLS certificate signing for ~6 hours.

**Evidence (ftc logs):**
- `citadelclient failed to sign CSR: create certificate: rpc error: code = Unavailable`
- `cache resource:default failed to sign: create certificate: rpc error: code = Unavailable`
- Onset ~**08:00Z**, ramped to **~5,700/hr (09:00–13:00Z)**, tapered to ~1,286 by
  14:00Z, then stopped. Nothing in the prior ~36 hours. Identical across all
  USAi services (chat, api, console-api, …) — i.e. mesh-wide, not app-specific.

**Impact:** when Citadel can't sign workload certs, sidecar mTLS fails and service
health checks fail across the mesh. This is the **likely root cause of the
same-morning multi-tenant Synthetics outages** (`chat.<tenant>.usai.gov/health`
failing ~3–9am across doi/opm/stateoig). Nothing paged on it proactively.

**Ask:** root-cause the istiod/Citadel `Unavailable` window (control-plane
restart? CA backend connectivity? resource pressure?). It recovered on its own,
but a 6-hour mesh-wide cert-signing gap that takes down health checks warrants a
look. Note this is distinct from the existing FCS-managed
`EMERGENCY … istio proxy control plane` monitor, which did not catch the
cert-signing signal.

**Now monitored:** `istio - mTLS certificate signing failing (control-plane)`
(>50/5m crit) + Infra Health dashboard "istio Citadel" section.

---

## 2. DocumentDB endpoint DNS-resolution failures

**What:** console-api's DocumentDB health check intermittently fails to resolve
the cluster endpoint.

**Evidence (ftc logs):**
- `MongoDB health check failed: usai-ftc-core-production-usai-ftc.cluster-….docdb.amazonaws.com:27017: [Errno -3] Try again (configured timeouts: connectTimeoutMS: 20000.0ms)`
- `[Errno -3]` = `EAI_AGAIN`, a **temporary DNS resolution failure**. Rare —
  2 events in the 7 days to 2026-06-23.
- The DocumentDB cluster itself is **healthy** during these (CPU ~14%, buffer
  cache 100%, connections nominal) — so this is **DNS/network reachability**, not
  database load or a cluster fault.

**Likely causes:** in-cluster CoreDNS capacity/throttling, the Route53 record for
the DocDB endpoint, or a brief cluster failover/maintenance window.

**Ask:** check CoreDNS health/capacity in the tenant clusters and DNS resolution
for the `*.docdb.amazonaws.com` endpoints. Low-volume today, but it's the kind of
signal that precedes a wider DNS problem.

**Now monitored:** `DocumentDB - health check failing (DNS / reachability)`
(>5/10m crit, >1 warn) + Infra Health dashboard "DocumentDB" section (failure
logs alongside cluster connections/CPU to disambiguate DNS-vs-DB).

---

## Note on log quality (context for both)

These signals were partly obscured because several USAi services log in plain
text, so Datadog indexes their level incorrectly (everything as `status:error`).
A fix is in flight for console-api (`gsai-core-console-api` PR #179, JSON
logging). Until structured logging lands everywhere, the dashboards match error
**content**, not the `status` tag.
