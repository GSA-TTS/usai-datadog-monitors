# Per-tenant USAi application health & errors dashboard.
#
# Complements the model-backend dashboard (which covers Bedrock/Azure backends).
# This one covers the USAi APPLICATION layer — the services that serve users:
# chat, api, console-api, console-pipeline-api, pipelines, embedding-proxy.
#
# Signal sourcing (verified against live ftc data 2026-06-23):
#   - ERRORS come from LOGS, matched by message CONTENT (genuine_error_query),
#     NOT the status tag — log levels aren't parsed from the message body so
#     status:error is dominated by mislabeled INFO/DEBUG. APM span-error metrics
#     (trace.*.request.errors) are also not populated in these orgs.
#   - LATENCY / THROUGHPUT come from APM (trace.fastapi/aiohttp.request.*).
#     fastapi covers chat/pipelines/embedding-proxy; chat also emits aiohttp.
#
# Instantiated once per tenant via the enclosing module.

locals {
  # USAi user-facing services (log `service` facet values).
  usai_app_services = "chat,api,console-api,console-pipeline-api,pipelines,embedding-proxy"

  app_services_or = replace(local.usai_app_services, ",", " OR ")

  # The Datadog `status` tag is UNRELIABLE for these services: log levels are not
  # parsed out of the message body, so INFO/DEBUG lines get indexed as
  # status:error (verified 2026-06-23 — see the console-api JSON-logging fix).
  # Until that lands everywhere, surface GENUINE errors by full-text matching the
  # word `error` while EXCLUDING the two big noise sources that also contain it:
  #   - ddtrace debug span dumps ("finishing span ... error=0 ...") — these are
  #     DEBUG-level tracer output, not errors; they carry the literal `error=0`.
  #   - "starting span" — the matching tracer open event.
  # What survives is real: "error probes Request to probe app failed", stack
  # traces, and genuine ERROR-level lines. Verified on ftc: the noisy form drops
  # ~all matches and only true errors (e.g. health-probe failures) remain.
  genuine_error_query = "env:production service:(${local.app_services_or}) error -\"finishing span\" -\"starting span\" -\"error=0\""
}

resource "datadog_dashboard" "app_health" {
  title       = "[${var.tenant}] USAi App Health & Errors"
  description = "Application-layer health for USAi services (chat, api, console, pipelines, embedding-proxy). Errors from logs, latency/throughput from APM. Managed by Terraform."
  layout_type = "ordered"
  reflow_type = "auto"

  # ---- Section: Errors (log-based) -------------------------------------------
  widget {
    note_definition {
      content          = "## Errors (logs)\nThe Datadog `status` tag is **unreliable** for these services — log levels aren't parsed from the message body, so INFO/DEBUG lines index as `status:error`. The widgets below instead match the word `error` while **excluding** the two big noise sources that also contain it: ddtrace debug span dumps (`finishing span … error=0`) and their `starting span` events. What remains is genuine — health-probe failures, stack traces, real ERROR lines. The `status` mix is shown last to expose the mislabeling until the source logging fix lands."
      background_color = "red"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  # Genuine errors over time, split by service — the headline error view, by
  # CONTENT match rather than the unreliable status tag.
  widget {
    timeseries_definition {
      title = "Genuine errors by service (content match)"
      request {
        display_type = "bars"
        log_query {
          index        = "*"
          search_query = local.genuine_error_query
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

  # Ranked error count by service. NOTE: grouping by an error-message/type facet
  # (e.g. @error.message) is NOT possible yet — these services emit no structured
  # log attributes, so there is nothing to group on but `service`. Once the source
  # JSON-logging fix lands (console-api etc.), add an @error.kind / @error.message
  # toplist here for true "count by error type".
  widget {
    toplist_definition {
      title = "Top error-producing services (genuine errors)"
      request {
        log_query {
          index        = "*"
          search_query = local.genuine_error_query
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

  # Live stream of the actual genuine-error log lines — the "show me the details"
  # widget. Lets an on-call read the real messages without leaving the dashboard.
  widget {
    list_stream_definition {
      title = "Recent error logs (live)"
      request {
        response_format = "event_list"
        query {
          data_source  = "logs_stream"
          query_string = local.genuine_error_query
          indexes      = ["*"]
        }
        columns {
          field = "timestamp"
          width = "auto"
        }
        columns {
          field = "service"
          width = "auto"
        }
        columns {
          field = "content"
          width = "auto"
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
          search_query = "env:production service:(${replace(local.usai_app_services, ",", " OR ")})"
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
        q            = "sum:trace.fastapi.request.hits{$service} by {service}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Avg request latency by service (fastapi, ms)"
      request {
        q            = "avg:trace.fastapi.request.duration{$service} by {service}"
        display_type = "line"
      }
      # 1s warning / 3s critical reference lines (duration is reported in ms here).
      marker {
        value        = "y = 1000"
        display_type = "warning dashed"
        label        = "1s"
      }
      marker {
        value        = "y = 3000"
        display_type = "error dashed"
        label        = "3s"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Chat aiohttp request latency (avg, ms)"
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
        q            = "sum:trace.postgres.connection.rollback.hits{$service}.as_count()"
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
