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
          content          = "One log event per tool invocation (`@event:\"Tool call\"`), so these counts are individual calls rather than requests — `@request_id` is shared by every call in one request, `@call_id` is unique per call. Over the 7 days sampled on 2026-09-16, **`web_search` was 4220 of 4353 calls (97%)**; `get_user_guide` 130; `run_code`, `gemini_rephrase` and `date_calculator` one each. A sudden change in that mix is usually a prompt or tool-config change rather than user behaviour.\n\n**This row counts attempts, not successes.** No completion event exists, so a call appearing here means the model asked for the tool — not that the tool worked. See the denial row for the only outcome signal available."
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
          content          = "The two failure events the app does emit:\n\n- **`Tool execution denied`** — the tool was recognised but refused. `@reason` explains it: over 7 days, `disabled` 16, `unregistered` 1. `disabled` means the tool is switched off for that tenant/config, so a rise here after a config change is expected and after no change is worth asking about.\n- **`Model called unregistered tool`** — the model hallucinated a tool that does not exist. Only 2 in 7 days; a spike suggests a prompt or tool-schema regression.\n\n**Baseline is very low: 19 failures against ~4353 attempts, about 0.4%.** Treat a sustained deny share above a few percent as a real signal rather than noise, and read `@reason` before escalating — `disabled` is configuration, `unregistered` is a model or schema problem, and they need different people.\n\nThese counts are NOT the inverse of success. A call absent from this row was *attempted*, not necessarily *completed* — there is no completion event to compare against."
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
          content          = "Tool calls broken down by the model that requested them (`@model`). Fixed group_by rather than a picker, because 1 of 17 denials carries no `@model` and a `@model:*` filter would silently hide it.\n\nMeasured 2026-09-16 over 7 days: **`gpt_5_5_default_v2` alone accounted for 2248 of 4343 tool calls (52%)**, then `claude-opus-5` 543, `claude_4_6_sonnet` 350, `claude_4_8_opus` 313. That concentration matters operationally — `gpt-5.5` is the deployment hitting the Azure quota ceiling (GSA-TTS/usai#1322), so tool-heavy traffic and the throttled model are the same traffic. If tool volume shifts onto a different model, expect the throttling profile to move with it."
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
          content          = "The individual events behind every count above, so a specific call can be read without leaving the board. Useful fields when drilling in: `@call_id` (this call), `@request_id` (all calls in the same request), `@conversation_id` (the user's thread), `@tool_name`, `@model`, `@reason` on denials, and `@client_ip`.\n\nThe stream is scoped to tool events only. Widen the query in place to `@tool_name:*` to include anything new the app starts emitting — worth doing occasionally, since a new `@event` value would otherwise be invisible on this board until someone adds a widget for it."
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
