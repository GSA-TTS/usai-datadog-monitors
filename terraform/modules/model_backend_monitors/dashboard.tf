# Per-tenant model-backend triage dashboard.
#
# The 2026-06-02 GSA incident was slow to diagnose because its two concurrent
# failure modes lived in different systems: AWS Bedrock model latency (metrics)
# and Azure OpenAI 429s + aborted streams (app logs). Nobody had a single view
# correlating them. This dashboard is that view — Bedrock metrics on the left,
# Azure OpenAI log signals on the right, so an on-call can see at a glance which
# backend is degrading.
#
# Instantiated once per tenant via the enclosing module, so each tenant org gets
# its own dashboard authed through that org's datadog provider.

resource "datadog_dashboard" "model_backend" {
  title       = "[${var.tenant}] Model Backend Health — Bedrock + Azure OpenAI"
  description = "Triage view for model-backend incidents (see the 2026-06-02 GSA incident). Bedrock metrics + Azure OpenAI log signals correlated. Managed by Terraform."
  layout_type = "ordered"
  reflow_type = "auto"

  # ---- Section: AWS Bedrock --------------------------------------------------
  widget {
    note_definition {
      content          = "## AWS Bedrock\nModel-side metrics via the Datadog AWS integration (`aws.bedrock.*`), grouped by model. **Latency is the leading indicator** — the incident was latency degradation with zero throttles."
      background_color = "blue"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "Bedrock - Avg Invocation Latency by model (ms)"
      request {
        q            = "avg:aws.bedrock.invocation_latency{*} by {modelid}"
        display_type = "line"
      }
      # Reference lines for the monitor thresholds (20s warn / 30s crit).
      marker {
        value        = "y = 20000"
        display_type = "warning dashed"
        label        = "warn 20s"
      }
      marker {
        value        = "y = 30000"
        display_type = "error dashed"
        label        = "crit 30s"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Bedrock - Invocation Throughput by model (count)"
      request {
        q            = "sum:aws.bedrock.invocations{*} by {modelid}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Bedrock - Throttles by model (count)"
      request {
        q            = "sum:aws.bedrock.invocation_throttles{*} by {modelid}.as_count()"
        display_type = "bars"
        style {
          palette = "warm"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Bedrock - Server Errors (5xx) by model (count)"
      request {
        q            = "sum:aws.bedrock.invocation_server_errors{*} by {modelid}.as_count()"
        display_type = "bars"
        style {
          palette = "warm"
        }
      }
    }
  }

  # ---- Section: Azure OpenAI -------------------------------------------------
  widget {
    note_definition {
      content          = "## Azure OpenAI (GPT)\nSignal lives ONLY in the `api` service logs — no AWS/Bedrock metric shows it. HTTP 429 throttling and chat streams aborted mid-flight were the user-visible half of the 2026-06-02 incident."
      background_color = "purple"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "Azure OpenAI - 'Too Many Requests' / 429 (api service, count)"
      request {
        display_type = "bars"
        log_query {
          index        = "*"
          search_query = "service:api env:production \"Too Many Requests\""
          compute_query {
            aggregation = "count"
          }
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Azure OpenAI - Streams aborted mid-flight (api service, count)"
      request {
        display_type = "bars"
        log_query {
          index        = "*"
          search_query = "service:api env:production \"Stream aborted mid-flight\""
          compute_query {
            aggregation = "count"
          }
        }
      }
    }
  }

  template_variable {
    name             = "modelid"
    prefix           = "modelid"
    available_values = []
    defaults         = ["*"]
  }
}
