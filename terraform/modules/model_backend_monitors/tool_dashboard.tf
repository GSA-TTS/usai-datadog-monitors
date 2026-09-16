# Per-tenant Tool Calls dashboard — which tools the models invoke, and what gets
# denied.
#
# Motivated by a 2026-09-16 `Tool execution denied` warn on gsa api-beta
# (`tool_name: web_search`, `reason: disabled`) and the question it prompted:
# can we see individual tool calls and their outcome on a board?
#
# Half of that is already possible and this board does it. The other half is not,
# and the notes below say so rather than shipping a widget that reads green
# through a blind spot.
#
# WHAT IS ACTUALLY LOGGED. Unlike the istio access logs (raw text, no attributes)
# and console-api (severity mis-mapped, GSA-TTS/usai#1377), these events are fully
# structured. Verified live against the gsa org on 2026-09-16 over a 7-day window:
#
#   @event   Tool call                        4338   <- one event per invocation
#            Tool execution denied              17   <- carries @reason
#            Model called unregistered tool      2
#
#   @tool_name  web_search 4220 · get_user_guide 130 · run_code 1
#               gemini_rephrase 1 · date_calculator 1
#   @reason     disabled 16 · unregistered 1        (denials only)
#   @model      19 distinct; gpt_5_5_default_v2 2248 dominates, then
#               claude-opus-5 543, claude_4_6_sonnet 350, claude_4_8_opus 313
#
# All 4343 events are service:api-beta and all carry env:production, so both are
# safe to pin in every widget scope. Other queryable attributes not charted here
# but present for drill-down: @call_id (per call), @request_id (shared by the
# calls in one request), @conversation_id, @client_id, @client_ip, @user_agent.
#
# ---------------------------------------------------------------------------
# TWO LIMITS THAT SHAPE THIS BOARD. Both were measured, not assumed.
#
# 1. THERE IS NO OUTCOME EVENT. `Tool call` is an INVOCATION record. Nothing is
#    emitted when a tool finishes, fails or returns, and no success/status/error
#    field exists on the event. So this board can show attempted-vs-denied, and
#    it CANNOT show succeeded-vs-errored. A "tool success rate" widget would be
#    measuring nothing. Closing that needs an app-side completion event; tracked
#    separately rather than faked here.
#
# 2. @latency_ms IS ALWAYS ZERO. Across all 4357 tool events in the 7-day window,
#    max(@latency_ms) = 0 and avg(@latency_ms) = 0 — on successes and denials
#    alike. The field is present but never populated, so there is deliberately no
#    latency widget. Do not add one until the app writes a real duration.
#
# ONE TEMPLATE VARIABLE, ON PURPOSE. `$tool_name` is wired into every widget
# scope below, per repo convention (PRs #4 and #8: a declared-but-unreferenced
# picker silently filters nothing). A `@model` picker was considered and REJECTED:
# 1 of the 17 denials carries no @model attribute, so a picker defaulting to `*`
# would render `@model:*` and silently drop that denial from every widget — the
# same class of bug as the $realm/$event_type trap on the Keycloak board. Model
# breakdown is therefore a fixed group_by, not a filter.
# ---------------------------------------------------------------------------
#
# Instantiated once per tenant via the enclosing module. Layout follows
# deploy_dashboard.tf: ordered groups, each opening with a colour-matched note
# that says how to read the rows beneath it.

resource "datadog_dashboard" "tool_calls" {
  title       = "[${var.tenant}] Tool Calls — invocation mix, denials, model attribution"
  description = "Individual tool invocations from the chat API: which tools are called, what gets denied and why, and which models drive tool use. Sourced from structured api-beta application logs (@event/@tool_name/@reason/@model). NOTE: there is no tool-completion event and @latency_ms is always 0, so success rate and latency are deliberately absent - see the file header. Managed by Terraform."
  layout_type = "ordered"
  reflow_type = "auto"

  # ==== Group: Tool call volume & mix =========================================
  widget {
    group_definition {
      title            = "Tool call volume & mix"
      layout_type      = "ordered"
      background_color = "blue"

      widget {
        note_definition {
          content          = "One event per tool invocation, not per request — `@request_id` groups the calls in one request. **These are attempts, not successes:** no completion event exists, so nothing here says the tool worked."
          background_color = "blue"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        query_value_definition {
          title     = "Tool calls (attempted)"
          autoscale = true
          precision = 0
          request {
            log_query {
              index        = "*"
              search_query = "service:api-beta env:production @event:\"Tool call\" $tool_name"
              compute_query {
                aggregation = "count"
              }
            }
            aggregator = "sum"
          }
        }
      }

      widget {
        timeseries_definition {
          title = "Tool calls over time, by tool"
          request {
            display_type = "bars"
            log_query {
              index        = "*"
              search_query = "service:api-beta env:production @event:\"Tool call\" $tool_name"
              compute_query {
                aggregation = "count"
              }
              group_by {
                facet = "@tool_name"
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

      widget {
        toplist_definition {
          title = "Calls by tool"
          request {
            log_query {
              index        = "*"
              search_query = "service:api-beta env:production @event:\"Tool call\" $tool_name"
              compute_query {
                aggregation = "count"
              }
              group_by {
                facet = "@tool_name"
                limit = 15
                sort_query {
                  aggregation = "count"
                  order       = "desc"
                }
              }
            }
          }
        }
      }
    }
  }

  # ==== Group: Denials & unregistered tools ===================================
  widget {
    group_definition {
      title            = "Denials & unregistered tools — the only outcome signal there is"
      layout_type      = "ordered"
      background_color = "orange"

      widget {
        note_definition {
          content          = "The only outcome signal the app emits. `@reason` routes it: **`disabled`** = tool switched off for this tenant (config), **`unregistered`** = the model invented a tool that doesn't exist (prompt/schema). Baseline is ~0.4% of attempts.\n\nDenials cluster by model rather than by volume — the heaviest tool caller is absent from them. ~7% of denials carry no `@model`, so the by-model row can sum below the totals."
          background_color = "orange"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        query_value_definition {
          title     = "Denied tool executions"
          autoscale = true
          precision = 0
          request {
            log_query {
              index        = "*"
              search_query = "service:api-beta env:production @event:\"Tool execution denied\" $tool_name"
              compute_query {
                aggregation = "count"
              }
            }
            aggregator = "sum"
          }
        }
      }

      widget {
        query_value_definition {
          title     = "Unregistered tools called by a model"
          autoscale = true
          precision = 0
          request {
            log_query {
              index        = "*"
              search_query = "service:api-beta env:production @event:\"Model called unregistered tool\" $tool_name"
              compute_query {
                aggregation = "count"
              }
            }
            aggregator = "sum"
          }
        }
      }

      widget {
        timeseries_definition {
          title = "Denials over time, by reason (disabled = config, unregistered = model/schema)"
          request {
            display_type = "bars"
            log_query {
              index        = "*"
              search_query = "service:api-beta env:production @event:(\"Tool execution denied\" OR \"Model called unregistered tool\") $tool_name"
              compute_query {
                aggregation = "count"
              }
              group_by {
                facet = "@reason"
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

      widget {
        toplist_definition {
          title = "Which tools get denied"
          request {
            log_query {
              index        = "*"
              search_query = "service:api-beta env:production @event:(\"Tool execution denied\" OR \"Model called unregistered tool\") $tool_name"
              compute_query {
                aggregation = "count"
              }
              group_by {
                facet = "@tool_name"
                limit = 15
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

      # Denials attributed to the requesting model. Deliberately NOT filtered on
      # @model:* — the group_by already drops events without the attribute, and
      # adding the filter would also change the widget's own denominator. 27 of 29
      # denials carry @model (93%) as measured 2026-09-16 over 30d, so this can sum
      # slightly below the counts above; that is expected, not a bug.
      widget {
        toplist_definition {
          title = "Denials by model"
          request {
            log_query {
              index        = "*"
              search_query = "service:api-beta env:production @event:(\"Tool execution denied\" OR \"Model called unregistered tool\") $tool_name"
              compute_query {
                aggregation = "count"
              }
              group_by {
                facet = "@model"
                limit = 20
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
  }

  # ==== Group: Model attribution ==============================================
  widget {
    group_definition {
      title            = "Model attribution — which models drive tool use"
      layout_type      = "ordered"
      background_color = "purple"

      widget {
        note_definition {
          content          = "Tool calls by the model that requested them. A fixed breakdown rather than a picker, because some denials carry no `@model` and a `@model:*` filter would hide them."
          background_color = "purple"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        timeseries_definition {
          title = "Tool calls over time, by model"
          request {
            display_type = "area"
            log_query {
              index        = "*"
              search_query = "service:api-beta env:production @event:\"Tool call\" $tool_name"
              compute_query {
                aggregation = "count"
              }
              group_by {
                facet = "@model"
                limit = 12
                sort_query {
                  aggregation = "count"
                  order       = "desc"
                }
              }
            }
          }
        }
      }

      widget {
        toplist_definition {
          title = "Calls by model"
          request {
            log_query {
              index        = "*"
              search_query = "service:api-beta env:production @event:\"Tool call\" $tool_name"
              compute_query {
                aggregation = "count"
              }
              group_by {
                facet = "@model"
                limit = 20
                sort_query {
                  aggregation = "count"
                  order       = "desc"
                }
              }
            }
          }
        }
      }
    }
  }

  # ==== Group: Raw events =====================================================
  widget {
    group_definition {
      title            = "Raw tool events — drill down to a single call"
      layout_type      = "ordered"
      background_color = "gray"

      widget {
        note_definition {
          content          = "The individual events behind the counts above. Drill in with `@call_id` (this call), `@request_id` (all calls in the request), or `@conversation_id` (the user's thread)."
          background_color = "gray"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        list_stream_definition {
          title = "Recent tool calls & denials (live)"
          request {
            response_format = "event_list"
            query {
              data_source  = "logs_stream"
              query_string = "service:api-beta env:production @event:(\"Tool call\" OR \"Tool execution denied\" OR \"Model called unregistered tool\") $tool_name"
              indexes      = ["*"]
            }
            columns {
              field = "timestamp"
              width = "auto"
            }
            columns {
              field = "@event"
              width = "auto"
            }
            columns {
              field = "@tool_name"
              width = "auto"
            }
            columns {
              field = "@model"
              width = "auto"
            }
            columns {
              field = "@reason"
              width = "auto"
            }
            columns {
              field = "content"
              width = "auto"
            }
          }
        }
      }
    }
  }

  # Tool picker — wired into EVERY widget scope above ($tool_name), per repo
  # convention. Default "*" shows all tools. Deliberately the only variable on
  # this board; see the file header for why a @model picker was rejected.
  template_variable {
    name             = "tool_name"
    prefix           = "@tool_name"
    available_values = []
    defaults         = ["*"]
  }
}
