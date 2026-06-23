# Per-tenant USAi application health & errors dashboard.
#
# Complements the model-backend dashboard (which covers Bedrock/Azure backends).
# This one covers the USAi APPLICATION layer — the services that serve users:
# chat, api, console-api, console-pipeline-api, pipelines, embedding-proxy.
#
# Signal sourcing (verified against live ftc data 2026-06-23):
#   - ERRORS come from LOGS (status:error by service). APM span-error metrics
#     (trace.*.request.errors) are not populated in these orgs, so log status
#     is the authoritative error signal — same mechanism as the Azure monitors.
#   - LATENCY / THROUGHPUT come from APM (trace.fastapi/aiohttp.request.*).
#     fastapi covers chat/pipelines/embedding-proxy; chat also emits aiohttp.
#
# Instantiated once per tenant via the enclosing module.

locals {
  # USAi user-facing services (log `service` facet values).
  usai_app_services = "chat,api,console-api,console-pipeline-api,pipelines,embedding-proxy"
}

resource "datadog_dashboard" "app_health" {
  title       = "[${var.tenant}] USAi App Health & Errors"
  description = "Application-layer health for USAi services (chat, api, console, pipelines, embedding-proxy). Errors from logs, latency/throughput from APM. Managed by Terraform."
  layout_type = "ordered"
  reflow_type = "auto"

  # ---- Section: Errors (log-based) -------------------------------------------
  widget {
    note_definition {
      content          = "## Errors (logs)\n`status:error` across the USAi app services. APM span-error metrics are not populated in these orgs, so log status is the authoritative error signal."
      background_color = "red"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  # Total error-log volume over time, split by service — the headline error view.
  widget {
    timeseries_definition {
      title = "Error logs by service (status:error)"
      request {
        display_type = "bars"
        log_query {
          index        = "*"
          search_query = "status:error service:(${replace(local.usai_app_services, ",", " OR ")})"
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

  # Top-line error count per service (toplist) for the last window.
  widget {
    toplist_definition {
      title = "Top error-log producers (USAi services)"
      request {
        log_query {
          index        = "*"
          search_query = "status:error service:(${replace(local.usai_app_services, ",", " OR ")})"
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
      }
    }
  }

  # Log status mix — surfaces level-mapping problems (e.g. debug logged as error).
  widget {
    timeseries_definition {
      title = "Log volume by status (all USAi services)"
      request {
        display_type = "area"
        log_query {
          index        = "*"
          search_query = "service:(${replace(local.usai_app_services, ",", " OR ")})"
          compute_query {
            aggregation = "count"
          }
          group_by {
            facet = "status"
            limit = 6
            sort_query {
              aggregation = "count"
              order       = "desc"
            }
          }
        }
      }
    }
  }

  # ---- Section: Latency & throughput (APM) -----------------------------------
  widget {
    note_definition {
      content          = "## Latency & throughput (APM)\nRequest duration and volume from APM traces. `fastapi` covers chat / pipelines / embedding-proxy; `chat` also emits `aiohttp`."
      background_color = "blue"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "Request throughput by service (fastapi, hits)"
      request {
        q            = "sum:trace.fastapi.request.hits{*} by {service}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Avg request latency by service (fastapi, seconds)"
      request {
        q            = "avg:trace.fastapi.request.duration{*} by {service}"
        display_type = "line"
      }
      # 1s warning / 3s critical reference lines for a rough SLO eyeball.
      marker {
        value        = "y = 1"
        display_type = "warning dashed"
        label        = "1s"
      }
      marker {
        value        = "y = 3"
        display_type = "error dashed"
        label        = "3s"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Chat aiohttp request latency (avg, seconds)"
      request {
        q            = "avg:trace.aiohttp.request.duration{service:chat}"
        display_type = "line"
      }
    }
  }

  # ---- Section: Datastore (APM) ----------------------------------------------
  widget {
    note_definition {
      content          = "## Datastore\nPostgres commit/rollback latency from APM — a common root cause behind app errors and latency spikes."
      background_color = "purple"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "Postgres rollback rate (hits) — elevated rollbacks signal failing transactions"
      request {
        q            = "sum:trace.postgres.connection.rollback.hits{*}.as_count()"
        display_type = "bars"
        style {
          palette = "warm"
        }
      }
    }
  }

  template_variable {
    name             = "service"
    prefix           = "service"
    available_values = []
    defaults         = ["*"]
  }
}
