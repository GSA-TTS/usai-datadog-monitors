# Per-tenant Datadog ingest / usage dashboard.
#
# Surfaces what each tenant org is sending TO Datadog — the cost/volume drivers —
# so a runaway log producer is caught before it becomes a billing problem. This
# was motivated by finding (2026-06-23) that in ftc the `embedding-proxy` service
# alone emits ~10.8 GB/day of logs — ~82% of the org's entire log ingest — almost
# certainly misclassified/over-verbose logging rather than signal.
#
# Signal sourcing (verified against live ftc data 2026-06-23):
#   - datadog.estimated_usage.logs.ingested_bytes / .ingested_events (by service)
#   - datadog.estimated_usage.apm.ingested_bytes / .ingested_spans
#   - datadog.estimated_usage.{hosts, containers}
#   - datadog.estimated_usage.synthetics.api_test_runs
#   (metrics.custom is NOT populated in these orgs, so it is omitted.)
#
# Instantiated once per tenant via the enclosing module.

resource "datadog_dashboard" "dd_usage" {
  title       = "[${var.tenant}] Datadog Ingest & Usage"
  description = "What this org sends to Datadog (cost/volume drivers). Log ingest by service catches runaway producers before they become a billing problem. Managed by Terraform."
  layout_type = "ordered"
  reflow_type = "auto"

  # ---- Section: Log ingest (the dominant cost driver) ------------------------
  widget {
    note_definition {
      content          = "## Log ingest\nThe largest ingest driver. Watch for a single service dominating total volume — that usually means misclassified or over-verbose logging, not signal."
      background_color = "orange"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  # Headline: log bytes by service — the runaway-producer view.
  widget {
    timeseries_definition {
      title = "Log ingest bytes by service"
      request {
        q            = "sum:datadog.estimated_usage.logs.ingested_bytes{*} by {service}.as_count()"
        display_type = "bars"
      }
    }
  }

  # Top producers as a ranked list for the current window.
  widget {
    toplist_definition {
      title = "Top log-ingest producers (bytes)"
      request {
        q = "top(sum:datadog.estimated_usage.logs.ingested_bytes{*} by {service}.as_count(), 10, 'sum', 'desc')"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Total log ingest — bytes & events"
      request {
        q            = "sum:datadog.estimated_usage.logs.ingested_bytes{*}.as_count()"
        display_type = "area"
      }
      request {
        q              = "sum:datadog.estimated_usage.logs.ingested_events{*}.as_count()"
        display_type   = "line"
        on_right_yaxis = true
      }
    }
  }

  # ---- Section: APM ingest ---------------------------------------------------
  widget {
    note_definition {
      content          = "## APM ingest\nTrace spans and bytes ingested. Much smaller than logs in these orgs today, but worth tracking if tracing expands."
      background_color = "blue"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "APM ingest — bytes & spans"
      request {
        q            = "sum:datadog.estimated_usage.apm.ingested_bytes{*}.as_count()"
        display_type = "area"
      }
      request {
        q              = "sum:datadog.estimated_usage.apm.ingested_spans{*}.as_count()"
        display_type   = "line"
        on_right_yaxis = true
      }
    }
  }

  # ---- Section: Infrastructure footprint -------------------------------------
  widget {
    note_definition {
      content          = "## Infrastructure footprint\nBilled hosts, monitored containers, and synthetic test runs."
      background_color = "gray"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    query_value_definition {
      title = "Billed hosts (avg)"
      request {
        q          = "avg:datadog.estimated_usage.hosts{*}"
        aggregator = "avg"
      }
    }
  }

  widget {
    query_value_definition {
      title = "Monitored containers (avg)"
      request {
        q          = "avg:datadog.estimated_usage.containers{*}"
        aggregator = "avg"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Synthetics API test runs"
      request {
        q            = "sum:datadog.estimated_usage.synthetics.api_test_runs{*}.as_count()"
        display_type = "bars"
      }
    }
  }
}
