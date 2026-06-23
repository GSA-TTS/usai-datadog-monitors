# Per-tenant edge / request dashboard.
#
# The traffic-ingress layer: AWS ALB and the istio ingress gateway (envoy). This
# is the layer a synthetic health-check failure (e.g. chat.<tenant>.usai.gov/health)
# surfaces first — 5xx at the ALB or envoy before any app-service metric moves.
#
# Signal sourcing (verified against live ftc data 2026-06-23):
#   - ALB: aws.applicationelb.{request_count, httpcode_elb_5xx, httpcode_target_5xx,
#     httpcode_target_4xx} by {loadbalancer}.
#   - istio ingress: trace.envoy.proxy.{hits, errors, duration} for
#     service:istio-ingressgateway.istio-system. (aws.applicationelb.target_response_time
#     is NOT populated in these orgs, so envoy duration is the edge-latency signal.)
#   - envoy errors break down by {http.status_code} (e.g. 503).
#
# Instantiated once per tenant via the enclosing module.

resource "datadog_dashboard" "edge_request" {
  title       = "[${var.tenant}] Edge & Request Health — ALB + istio ingress"
  description = "Traffic-ingress health: AWS ALB status codes + istio ingress-gateway (envoy) hits/errors/latency. First place a health-check outage shows. Managed by Terraform."
  layout_type = "ordered"
  reflow_type = "auto"

  # ---- Section: AWS ALB ------------------------------------------------------
  widget {
    note_definition {
      content          = "## AWS ALB\nLoad-balancer request volume and HTTP status codes. `elb_5xx` = the ALB itself failed; `target_5xx` = the backend returned 5xx; `target_4xx` = client errors."
      background_color = "blue"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "ALB request volume by load balancer"
      request {
        q            = "sum:aws.applicationelb.request_count{$loadbalancer} by {loadbalancer}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "ALB 5xx — ELB-generated vs target (errors)"
      request {
        q            = "sum:aws.applicationelb.httpcode_elb_5xx{$loadbalancer}.as_count()"
        display_type = "bars"
        style {
          palette = "warm"
        }
      }
      request {
        q            = "sum:aws.applicationelb.httpcode_target_5xx{$loadbalancer}.as_count()"
        display_type = "bars"
        style {
          palette = "orange"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "ALB target 4xx (client errors)"
      request {
        q            = "sum:aws.applicationelb.httpcode_target_4xx{$loadbalancer}.as_count()"
        display_type = "bars"
      }
    }
  }

  # ---- Section: istio ingress gateway (envoy) --------------------------------
  widget {
    note_definition {
      content          = "## istio ingress gateway (envoy)\nThe service-mesh entry point. `errors` break down by `http.status_code`. Edge latency comes from envoy proxy duration (ALB `target_response_time` is not populated here)."
      background_color = "purple"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
    }
  }

  widget {
    timeseries_definition {
      title = "Ingress gateway request rate (envoy hits)"
      request {
        q            = "sum:trace.envoy.proxy.hits{service:istio-ingressgateway.istio-system}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Ingress gateway errors by HTTP status"
      request {
        q            = "sum:trace.envoy.proxy.errors{service:istio-ingressgateway.istio-system} by {http.status_code}.as_count()"
        display_type = "bars"
        style {
          palette = "warm"
        }
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Ingress gateway latency (envoy duration, avg ms)"
      request {
        q            = "avg:trace.envoy.proxy.duration{service:istio-ingressgateway.istio-system}"
        display_type = "line"
      }
    }
  }

  template_variable {
    name             = "loadbalancer"
    prefix           = "loadbalancer"
    available_values = []
    defaults         = ["*"]
  }
}
