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

  # NOTE: a "root cert expiry" query_value was intentionally omitted. The
  # istio.citadel.server.root_cert_expiry_timestamp metric is a Unix epoch value
  # (mislabeled unit:second) — e.g. ~2086827150 = 2036-02-17, ~3,500 days out for
  # a 10-year root cert — so a raw query_value renders a meaningless ~2.09e9
  # number, and the root cert is not the operational signal anyway (the incident
  # was WORKLOAD cert signing, shown above). A days-until-expiry widget would need
  # now() in the query, which Datadog formulas don't provide; if root-cert expiry
  # monitoring is wanted later, do it as a dedicated monitor with a relative
  # threshold rather than a dashboard number.

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
}
