# Shared monitor thresholds — the single source of truth for values that were
# previously hardcoded in 3-5 unbound places each (the monitor query string, the
# monitor_thresholds block, dashboard reference-line markers, and toplist
# conditional-format bands). A retune of any of these is now a one-line change
# here that propagates to the monitor AND every dashboard that visualizes it, so
# a threshold can no longer silently half-apply. See GitHub #33 (v0.3.0 retro
# finding: drift caught across PRs #29/#30/#31).
#
# Adding a new binding: reference the local from both the resource that ENFORCES
# the threshold (the monitor) and every resource that DISPLAYS it (dashboard
# markers/bands). Never re-type the literal.
locals {
  # Bedrock invocation-latency monitor (main.tf: bedrock_invocation_latency_high)
  # + Model Backend dashboard markers (dashboard.tf). Milliseconds.
  # Refit history: 30s -> 45s (PR #22) -> 60s/15m (PR #31, opus-4-8 variance).
  bedrock_latency_crit_ms          = 60000
  bedrock_latency_warn_ms          = 40000
  bedrock_latency_crit_recovery_ms = 50000
  bedrock_latency_warn_recovery_ms = 30000

  # Pod-restart-storm monitor (infra_monitors.tf: pod_restart_storm) + Deployments
  # & Rollouts dashboard pod-age markers and youngest-pods toplist bands
  # (deploy_dashboard.tf). Seconds (peak avg-pod-age over a 4h window).
  # Retune history: avg(4h)<1h (3600s) -> max(4h)<90m (5400s) (PR #29).
  pod_storm_critical_s          = 5400  # 90m — restart-storm trigger
  pod_storm_warning_s           = 7200  # 2h  — elevated-churn warning (no handle)
  pod_storm_critical_recovery_s = 10800 # 3h  — recovery hysteresis (above trigger)
  pod_storm_warning_recovery_s  = 14400 # 4h

  # The toplist widget plots pod age in MINUTES (pod.age/60), so its color bands
  # are the second-thresholds above expressed in minutes. Derived, not re-typed,
  # so they track a retune automatically. Currently 90m / 120m.
  pod_storm_critical_min = local.pod_storm_critical_s / 60
  pod_storm_warning_min  = local.pod_storm_warning_s / 60

  # Edge TLS cert-expiry thresholds (cert_monitors.tf: ssl_cert,
  # ssl_cert_expiring_soon, acm_cert_expiry). DAYS remaining, counting down — so
  # the warn value is LARGER than the crit value. Referenced from three resources
  # plus their message bodies; keep them here rather than in the feature file so a
  # retune can't half-apply (GitHub #33).
  cert_expiry_warn_days = 45 # warn early — cert generation takes ~15m + a PR
  cert_expiry_crit_days = 14 # crit — genuinely close, page it

  # Edge synthetic timing (cert_monitors.tf: edge_health, ssl_cert, https_reach).
  # Bound here because the same two values appear in every test's options_list AND
  # are quoted in the alert bodies ("failing for N minutes"), which is exactly the
  # half-applied-retune shape GitHub #33 called out.
  #
  # min_failure_duration deliberately NOT 0. The 16 hand-built UI tests these
  # resources replace used 0, so a single failed run paged — and combined with
  # renotify_interval:10 on the usda/ftc tests that produced the every-10-minute
  # re-trigger flood in the 2026-08-18 report. 300s means two consecutive failed
  # 5m runs before a page, which no single blip survives.
  edge_synthetic_tick_s        = 300 # run every 5m
  edge_synthetic_min_failure_s = 300 # must fail continuously 5m before alerting
  edge_synthetic_min_failure_m = 5   # same value in minutes, for message text

  # Re-page hourly, not every 10 minutes. An unreachable edge stays unreachable
  # until someone fixes it, so a single missed page is bad — but 10m across 25
  # orgs is the flood. 60m is the compromise the cert monitors' 1440 analogue
  # would be too slow for.
  edge_synthetic_renotify_min = 60
}
