# Per-tenant service-mesh / infrastructure health dashboard.
#
# Companion to the App Health dashboard. The 2026-06-23 ftc review found that
# ~all "errors" the app pods emit are actually INFRASTRUCTURE signals (istio
# mTLS, envoy xDS, dd-trace agent), so they were stripped from the App Health
# error view and surfaced here instead. The istio cert-signing burst that
# (likely) caused the multi-tenant synthetics outages would show on this board.
#
# Sourcing (verified against live ftc data 2026-06-23): istio control-plane
# METRICS (istio.citadel.*, istio.pilot.*, istio.go.*) for the mesh's own health,
# plus the LOG signals (cert-signing / envoy xDS / dd-agent) the app pods emit —
# the same signals infra_monitors.tf alerts on.
#
# Instantiated once per tenant via the enclosing module.

resource "datadog_dashboard" "infra_health" {
  title       = "[${var.tenant}] Service Mesh & Infra Health — istio / envoy / dd-agent"
  description = "Mesh/infrastructure health: istio control-plane (Citadel cert signing, Pilot xDS), plus the infra log signals excluded from App Health. Managed by Terraform."
  layout_type = "ordered"
  reflow_type = "auto"

  # ---- Section: istio Citadel — mTLS certificate signing ---------------------
  widget {
    note_definition {
      content          = "## istio Citadel — mTLS cert signing\nThe control-plane certificate authority. The 2026-06-23 incident was Citadel returning `rpc Unavailable` on workload cert signing for ~6h, which broke sidecar mTLS mesh-wide and failed health probes. `infra_monitors.tf` alerts on the log signal; these widgets show the metric view."
      background_color = "purple"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "Citadel - successful cert issuances (count)"
      request {
        q            = "sum:istio.citadel.server.success_cert_issuance_count{*}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Citadel - CSRs received vs successful issuances (a gap = signing failures)"
      request {
        q            = "sum:istio.citadel.server.csr_count{*}.as_count()"
        display_type = "line"
      }
      request {
        q            = "sum:istio.citadel.server.success_cert_issuance_count{*}.as_count()"
        display_type = "line"
      }
    }
  }

  # Cert-signing FAILURES from logs — the actual incident signal (what we alert on).
  widget {
    timeseries_definition {
      title = "istio mTLS cert-signing failures (logs) — alerted in infra_monitors.tf"
      request {
        display_type = "bars"
        log_query {
          index        = "*"
          search_query = "env:production (\"failed to sign CSR\" OR \"failed to sign\") (citadelclient OR cache)"
          compute_query {
            aggregation = "count"
          }
          group_by {
            facet = "service"
            limit = 10
            sort_query {
              aggregation = "count"
              order       = "desc"
            }
          }
        }
        style {
          palette = "warm"
        }
      }
    }
  }

  # Root cert: DAYS until expiry, not the raw epoch. The metric
  # (istio.citadel.server.root_cert_expiry_timestamp) is an absolute Unix epoch
  # (mislabeled unit:second), so showing it raw is meaningless. Datadog widget
  # queries have no now(), so the countdown subtracts the baked-in var.dashboard_epoch
  # anchor and divides by 86400 -> days remaining. The value drifts slowly as
  # wall-clock passes the anchor (over-counts), so re-stamp dashboard_epoch on
  # apply; fine for a multi-year root cert. Operationally the WORKLOAD cert
  # signing above is the live signal — this is a slow-burn "is the root cert
  # approaching expiry" check.
  widget {
    query_value_definition {
      title       = "Root cert — days until expiry (approx; re-stamp dashboard_epoch)"
      precision   = 0
      custom_unit = "days"
      request {
        q          = "(max:istio.citadel.server.root_cert_expiry_timestamp{*} - ${var.dashboard_epoch}) / 86400"
        aggregator = "last"
        conditional_formats {
          comparator = "<"
          value      = 30
          palette    = "white_on_red"
        }
        conditional_formats {
          comparator = "<"
          value      = 90
          palette    = "white_on_yellow"
        }
        conditional_formats {
          comparator = ">="
          value      = 90
          palette    = "white_on_green"
        }
      }
    }
  }

  # ---- Section: istio Pilot — xDS config distribution ------------------------
  widget {
    note_definition {
      content          = "## istio Pilot — xDS config distribution\nPilot pushes config (listeners/routes/clusters/endpoints) to the envoy sidecars over xDS. Push errors or rising convergence time mean sidecars run stale config. The envoy `AggregatedResources` warnings the apps log are the sidecar side of this."
      background_color = "blue"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "Pilot - xDS pushes (count)"
      request {
        q            = "sum:istio.pilot.xds.pushes{*}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Pilot - proxy convergence time (avg) — rising = sidecars slow to get config"
      request {
        # Time-weighted average across all istiod replicas: sum(sum)/sum(count).
        # (avg/avg would distort once there is more than one control-plane pod.)
        q            = "sum:istio.pilot.proxy_convergence_time.sum{*} / sum:istio.pilot.proxy_convergence_time.count{*}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "envoy xDS stream churn (logs) — config stream reconnects"
      request {
        display_type = "bars"
        log_query {
          index        = "*"
          search_query = "env:production service:(chat OR api OR console-api OR console-pipeline-api OR pipelines OR embedding-proxy) \"warning envoy\""
          compute_query {
            aggregation = "count"
          }
        }
      }
    }
  }

  # ---- Section: control-plane process + dd-agent -----------------------------
  widget {
    note_definition {
      content          = "## Control-plane process & dd-agent\nistiod process health (goroutines/GC as a liveness proxy) and the dd-trace/profiler agent's ability to ship telemetry. dd-agent send failures mean APM/trace data is being dropped — alerted in infra_monitors.tf."
      background_color = "gray"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "istiod - goroutines (process liveness proxy)"
      request {
        q            = "avg:istio.go.goroutines{*}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Datadog agent telemetry/trace send failures (logs) — alerted in infra_monitors.tf"
      request {
        display_type = "bars"
        log_query {
          index = "*"
          # Kept byte-identical to the dd_agent_telemetry_send_failures monitor
          # query (infra_monitors.tf) so the dashboard shows exactly what alerts.
          search_query = "env:production service:(chat OR api OR console-api OR console-pipeline-api OR pipelines OR embedding-proxy) (\"dropping\" \"traces to intake\" OR ddog_prof_Exporter_send OR \"Instrumentation Telemetry\")"
          compute_query {
            aggregation = "count"
          }
          group_by {
            facet = "service"
            limit = 10
            sort_query {
              aggregation = "count"
              order       = "desc"
            }
          }
        }
        style {
          palette = "warm"
        }
      }
    }
  }

  # ---- Section: Container OOMKilled -------------------------------------------
  widget {
    note_definition {
      content          = "## Container OOMKilled\nKernel cgroup OOM kills (exit 137). A burst here means a container is crash-looping because it hit its memory limit. The monitor alerts at >=2/10m. Check which deployment is affected and whether traffic, a leak, or an undersized limit is the cause."
      background_color = "red"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    event_timeline_definition {
      title          = "OOMKilled events (containerd) — each bar is a kill"
      query          = "source:containerd event_type:oom"
      tags_execution = "and"
    }
  }

  widget {
    event_stream_definition {
      title          = "OOMKilled events — live stream (deployment + pod)"
      query          = "source:containerd event_type:oom"
      event_size     = "s"
      tags_execution = "and"
    }
  }

  # ---- Section: Deployment Health --------------------------------------------
  widget {
    note_definition {
      content          = "## Deployment Health\nDesired vs ready replicas per deployment. A **sustained** gap (desired > ready for 30m+) is the alerted signal (infra_monitors.tf: \"Deployment lacks minimum availability\") — a stuck rollout, an orphaned/superseded deployment that can't converge, or pods that won't schedule (missing secret, node pressure). A brief gap during a normal rolling update is expected and self-clears. Motivated by GSA-TTS/usai#896, where a legacy frontend-apps deployment sat un-ready for a day with no visibility."
      background_color = "orange"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "Unavailable replicas by deployment (desired − ready) — alerted in infra_monitors.tf"
      request {
        q            = "max:kubernetes_state.deployment.replicas_desired{*} by {kube_namespace,kube_deployment} - max:kubernetes_state.deployment.replicas_ready{*} by {kube_namespace,kube_deployment}"
        display_type = "bars"
      }
      marker {
        value        = "y = 1"
        display_type = "warning dashed"
        label        = "1 replica short"
      }
    }
  }

  widget {
    toplist_definition {
      title = "Deployments currently short of desired (top offenders, last 30m)"
      request {
        q = "top(max:kubernetes_state.deployment.replicas_desired{*} by {kube_namespace,kube_deployment} - max:kubernetes_state.deployment.replicas_ready{*} by {kube_namespace,kube_deployment}, 10, 'max', 'desc')"
      }
    }
  }

  # ---- Section: DocumentDB (Mongo-compatible) --------------------------------
  widget {
    note_definition {
      content          = "## DocumentDB (MongoDB)\nconsole-api's backing store. The **health-check failures** below are the alerted signal (infra_monitors.tf) — usually DNS/reachability (`[Errno -3] Try again` resolving the cluster endpoint), not DB load. The **cluster metrics** are here to disambiguate: if connections/CPU look normal during a failure spike, it's DNS/network, not the database."
      background_color = "purple"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  # The alerted signal: health-check failure logs. Byte-identical to the
  # docdb_health_check_failing monitor query so the dashboard shows what alerts.
  widget {
    timeseries_definition {
      title = "DocumentDB - health check failures (logs) — alerted in infra_monitors.tf"
      request {
        display_type = "bars"
        log_query {
          index        = "*"
          search_query = "env:production service:console-api \"MongoDB health check failed\""
          compute_query {
            aggregation = "count"
          }
        }
        style {
          palette = "warm"
        }
      }
    }
  }

  # Cluster health, to disambiguate DNS/network from a real DB problem.
  widget {
    timeseries_definition {
      title = "DocumentDB - connections & CPU (cluster health)"
      request {
        q            = "avg:aws.docdb.database_connections{*}"
        display_type = "line"
      }
      request {
        q              = "avg:aws.docdb.cpuutilization{*}"
        display_type   = "line"
        on_right_yaxis = true
      }
    }
  }
}
