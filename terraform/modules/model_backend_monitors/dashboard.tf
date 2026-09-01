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
        q            = "avg:aws.bedrock.invocation_latency{$modelid} by {modelid}"
        display_type = "line"
      }
      # Reference lines for the monitor thresholds (40s warn / 60s crit,
      # bedrock_invocation_latency_high — refit to 60s/15m for the opus-4-8 mix).
      marker {
        value        = "y = ${local.bedrock_latency_warn_ms}"
        display_type = "warning dashed"
        label        = "warn 40s"
      }
      marker {
        value        = "y = ${local.bedrock_latency_crit_ms}"
        display_type = "error dashed"
        label        = "crit 60s"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Bedrock - Invocation Throughput by model (count)"
      request {
        q            = "sum:aws.bedrock.invocations{$modelid} by {modelid}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Bedrock - Throttles by model (count)"
      request {
        q            = "sum:aws.bedrock.invocation_throttles{$modelid} by {modelid}.as_count()"
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
        q            = "sum:aws.bedrock.invocation_server_errors{$modelid} by {modelid}.as_count()"
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

  # ── FIXED 2026-09-01: BOTH AZURE WIDGETS RENDERED EMPTY ────────────────────
  # They queried `service:api env:production "Too Many Requests"` and
  # `... "Stream aborted mid-flight"`. Measured against the live gsa logs API:
  # BOTH return ZERO events over 30 days, so both graphs had been blank.
  #
  # Two separate faults, found by probing rather than reasoning:
  #
  #   1. WRONG SERVICE SCOPE. Azure OpenAI work is split across TWO services now,
  #      `api` and `api-beta`, and the throttle signal appears under BOTH —
  #      measured over 14d in gsa: api=2801, api-beta=2609, and 5410 with
  #      `service:(api OR api-beta)`. Neither service alone captures it, so the
  #      OR form is not defensive padding, it is required for a correct count.
  #
  #   2. WRONG PHRASE. The log text is not "Too Many Requests" — that string
  #      appears only in cloudtrail logs in these orgs. Azure's actual wording is
  #      e.g. "Your requests to gpt-5.5 for gpt-5.5-latest-guardrails-defaultv2
  #      in eastus2 have exceeded rate limit." So the match is "exceeded rate
  #      limit". 4509 events in gsa over 7d — this has been happening constantly
  #      with nothing displaying it.
  #
  # "Stream aborted mid-flight" is worse: that phrase returns 0 across ALL
  # services and all of env:production over 30 days, and so do "stream aborted",
  # "aborted mid-flight" and bare "abort". The signal the second widget was built
  # for (the 2026-06-02 incident) no longer exists in the logs at all, so pointing
  # it at a variant would just be a different empty graph. It is repurposed to the
  # upstream-500 signal that DOES exist (78 events/7d in gsa, e.g. "500: Internal
  # Server Error | headers: {...'Server': 'envoy'...}"), which is the closest real
  # measure of Azure-side failures reaching users.
  #
  # NOTE the same two broken queries are still live in main.tf's two Azure
  # monitors, where on_missing_data="default" has kept them permanently green
  # while matching nothing. That is a silent-monitor bug, not a display bug, and it
  # is deliberately NOT fixed in this PR — see the monitor-side note in main.tf.
  widget {
    timeseries_definition {
      title = "Azure OpenAI - rate limited by Azure ('exceeded rate limit', api + api-beta)"
      request {
        display_type = "bars"
        log_query {
          index        = "*"
          search_query = "service:(api OR api-beta) env:production \"exceeded rate limit\""
          compute_query {
            aggregation = "count"
          }
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Azure OpenAI - upstream 500s reaching the app (api + api-beta)"
      request {
        display_type = "bars"
        log_query {
          index        = "*"
          search_query = "service:(api OR api-beta) env:production \"Internal Server Error\""
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
