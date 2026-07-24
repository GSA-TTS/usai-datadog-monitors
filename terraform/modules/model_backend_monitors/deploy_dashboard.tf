# Per-tenant Deployments & Rollouts dashboard.
#
# Companion to the pod-restart-storm / deployment-availability monitors
# (infra_monitors.tf). Motivated by GSA-TTS/usai#1095 (2026-07-22): a restart
# storm on doc/ftc core deployments that was INVISIBLE to a restart-count view
# (fresh pods start at 0 restarts) and to a desired-vs-ready view (churning pods
# keep reaching Ready). This board surfaces every aspect of a deploy so the two
# distinct failure modes we root-caused are each visible at a glance:
#   - Problem 1 — HPA memory thrash: chat's memory utilization sitting at/above
#     the 80% HPA target drove perpetual scale-up/scale-down (fixed by
#     gsai-flux-mono PR #370, request 1000Mi -> 1500Mi -> ~59% util).
#   - Problem 2 — fleet-wide rollout churn: the shared stateless-application
#     HelmChart re-cut on every git revision (reconcileStrategy: Revision), so
#     any image push in any env rolls every deployment. Shows up as pod age that
#     never grows + many concurrent ReplicaSets.
#
# Sourcing verified live against doc kube-state-metrics (2026-07-23):
#   kubernetes_state.pod.age / .deployment.replicas{,_desired,_updated,_unavailable}
#   / .hpa.{current,desired,min,max}_replicas by {horizontalpodautoscaler}
#   / .replicaset.replicas_desired by {kube_replica_set} / .container.restarts,
#   plus kubernetes.memory.{usage,requests} and kubernetes.cpu.usage.total, and
#   source:kubernetes events (HelmRelease / ReplicaSet scaling). Per repo
#   convention the $kube_namespace template variable is wired into EVERY widget
#   scope so the picker actually filters.
#
# Instantiated once per tenant via the enclosing module.

resource "datadog_dashboard" "deployments" {
  title       = "[${var.tenant}] Deployments & Rollouts — scaling, rollout health, restart churn"
  description = "Every aspect of a deploy: replica scaling (HPA), rollout progress, pod-age churn (restart-storm signal), and Kubernetes rollout events. Companion to the pod-restart-storm / deployment-availability monitors. Motivated by GSA-TTS/usai#1095. Managed by Terraform."
  layout_type = "ordered"
  reflow_type = "auto"

  # ==== Group: Pod age & rollout churn ========================================
  widget {
    group_definition {
      title            = "Pod age & rollout churn"
      layout_type      = "ordered"
      background_color = "orange"

      widget {
        note_definition {
          content          = "The clean restart-storm discriminator. Healthy deployments age their pods to hours/days; a deployment being continuously replaced can never let its pods get old. The `pod_restart_storm` alert (infra_monitors.tf) fires when the **peak** avg pod age over a 4h window never climbs past 90m — so this line hugging or staying under the 90m marker is the alert signal (restart-count is blind to this because fresh pods start at 0 restarts). **Active ReplicaSets**: many concurrent ReplicaSets on one deployment = repeated rollouts (the Problem 2 signature — chart re-cut on every git revision)."
          background_color = "orange"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        timeseries_definition {
          title = "Average pod age by deployment — peak-over-4h < 90m = restart storm (alerted)"
          request {
            q            = "avg:kubernetes_state.pod.age{$kube_namespace} by {kube_deployment}"
            display_type = "line"
          }
          marker {
            value        = "y = ${local.pod_storm_critical_s}"
            display_type = "error dashed"
            label        = "90m — restart-storm threshold (critical)"
          }
          marker {
            value        = "y = ${local.pod_storm_warning_s}"
            display_type = "warning dashed"
            label        = "2h — elevated churn (warning)"
          }
        }
      }

      widget {
        toplist_definition {
          title = "Youngest pods right now, in minutes (deployments most likely cycling)"
          # pod.age is in seconds; /60 -> minutes so the value is legible. Colors
          # track the pod_restart_storm markers: < 90m (critical threshold) red,
          # < 120m (warning) yellow, >= 120m green. 'asc' surfaces the smallest
          # (youngest) first — the ones being replaced most aggressively.
          request {
            q = "top(avg:kubernetes_state.pod.age{$kube_namespace} by {kube_namespace,kube_deployment} / 60, 10, 'last', 'asc')"
            conditional_formats {
              comparator = "<"
              value      = local.pod_storm_critical_min
              palette    = "white_on_red"
            }
            conditional_formats {
              comparator = "<"
              value      = local.pod_storm_warning_min
              palette    = "white_on_yellow"
            }
            conditional_formats {
              comparator = ">="
              value      = local.pod_storm_warning_min
              palette    = "white_on_green"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title = "Active ReplicaSets (desired replicas by ReplicaSet) — many at once = repeated rollouts"
          request {
            q            = "max:kubernetes_state.replicaset.replicas_desired{$kube_namespace} by {kube_replica_set}"
            display_type = "bars"
          }
        }
      }
    }
  }

  # ==== Group: Replica scaling (HPA) ==========================================
  widget {
    group_definition {
      title            = "Replica scaling (HPA)"
      layout_type      = "ordered"
      background_color = "blue"

      widget {
        note_definition {
          content          = "Current vs desired vs the min/max bounds, per HorizontalPodAutoscaler. When **current** tracks **desired** smoothly, scaling is healthy. When desired oscillates between min and a high value (chat: min 8, max 400/50), the HPA is thrashing — the Problem 1 signature we root-caused on doc/ftc chat. Hitting **max** means the HPA is saturated and can't scale further."
          background_color = "blue"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        timeseries_definition {
          title = "HPA current vs desired replicas by autoscaler"
          request {
            q            = "max:kubernetes_state.hpa.current_replicas{$kube_namespace} by {horizontalpodautoscaler}"
            display_type = "line"
          }
          request {
            q            = "max:kubernetes_state.hpa.desired_replicas{$kube_namespace} by {horizontalpodautoscaler}"
            display_type = "line"
          }
        }
      }

      widget {
        timeseries_definition {
          title = "HPA bounds — desired vs min/max (at max = saturated; oscillating = thrash)"
          request {
            q            = "max:kubernetes_state.hpa.desired_replicas{$kube_namespace} by {horizontalpodautoscaler}"
            display_type = "line"
          }
          request {
            q            = "max:kubernetes_state.hpa.min_replicas{$kube_namespace} by {horizontalpodautoscaler}"
            display_type = "line"
            style {
              palette   = "grey"
              line_type = "dashed"
            }
          }
          request {
            q            = "max:kubernetes_state.hpa.max_replicas{$kube_namespace} by {horizontalpodautoscaler}"
            display_type = "line"
            style {
              palette   = "grey"
              line_type = "dashed"
            }
          }
        }
      }
    }
  }

  # ==== Group: Autoscaler drivers (utilization vs target) =====================
  widget {
    group_definition {
      title            = "Autoscaler drivers — utilization vs target"
      layout_type      = "ordered"
      background_color = "purple"

      widget {
        note_definition {
          content          = "What the HPA actually reads. chat scales on **memory @ 80%** and **CPU @ 75%**. Problem 1 was memory utilization sitting *at or above* 80% at every replica count (a per-pod baseline, not load-proportional), so the HPA could never satisfy the target and oscillated forever. gsai-flux-mono **PR #370** raised the chat memory request 1000Mi → 1500Mi, which should pull steady-state utilization down to ~59% (below target). Watch the memory line settle below the 80% marker after that rollout lands."
          background_color = "purple"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        timeseries_definition {
          title = "Memory utilization % (usage ÷ request) by deployment — HPA target 80%"
          request {
            q            = "avg:kubernetes.memory.usage{$kube_namespace} by {kube_deployment} / avg:kubernetes.memory.requests{$kube_namespace} by {kube_deployment} * 100"
            display_type = "line"
          }
          marker {
            value        = "y = 80"
            display_type = "error dashed"
            label        = "80% — memory HPA target"
          }
        }
      }

      widget {
        timeseries_definition {
          title = "Memory: working set vs request (chat request 1000→1500Mi in PR #370)"
          request {
            q            = "avg:kubernetes.memory.usage{$kube_namespace} by {kube_deployment}"
            display_type = "line"
          }
          request {
            q              = "avg:kubernetes.memory.requests{$kube_namespace} by {kube_deployment}"
            display_type   = "line"
            on_right_yaxis = false
            style {
              palette   = "grey"
              line_type = "dashed"
            }
          }
        }
      }
    }
  }

  # ==== Group: Rollout progress & availability ================================
  widget {
    group_definition {
      title            = "Rollout progress & availability"
      layout_type      = "ordered"
      background_color = "gray"

      widget {
        note_definition {
          content          = "A healthy rollout: **updated** climbs to meet **desired** while **unavailable** briefly rises then returns to 0. A rollout that is stuck (new pods failing readiness) or a deployment that can't converge shows **unavailable ≥ 1 sustained** — the `deployment_unavailable` alert signal (infra_monitors.tf, GSA-TTS/usai#896). During a restart storm you'll see this churn repeatedly rather than settle."
          background_color = "gray"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        timeseries_definition {
          title = "Rollout: desired vs updated replicas by deployment (gap = rollout in progress)"
          request {
            q            = "max:kubernetes_state.deployment.replicas_desired{$kube_namespace} by {kube_deployment}"
            display_type = "line"
          }
          request {
            q            = "max:kubernetes_state.deployment.replicas_updated{$kube_namespace} by {kube_deployment}"
            display_type = "line"
          }
        }
      }

      widget {
        timeseries_definition {
          title = "Unavailable replicas by deployment — sustained ≥ 1 is alerted (infra_monitors.tf)"
          request {
            q            = "max:kubernetes_state.deployment.replicas_unavailable{$kube_namespace} by {kube_deployment}"
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
        timeseries_definition {
          title = "Container restarts by deployment (cumulative) — flat during a restart storm"
          request {
            q            = "sum:kubernetes_state.container.restarts{$kube_namespace} by {kube_deployment}"
            display_type = "bars"
          }
        }
      }
    }
  }

  # ==== Group: Deploy events ==================================================
  widget {
    group_definition {
      title            = "Deploy events (Kubernetes / Flux)"
      layout_type      = "ordered"
      background_color = "vivid_blue"

      widget {
        note_definition {
          content          = "The actual rollout timeline: `ScalingReplicaSet`, ReplicaSet create/scale, and Flux HelmRelease/HelmChart reconciles. A burst of ReplicaSet events with no corresponding image-tag change is the Problem 2 fingerprint (chart re-cut per git revision). Correlate the timing here with the pod-age dips above."
          background_color = "vivid_blue"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        event_timeline_definition {
          title          = "Kubernetes rollout events — each bar is a scaling/reconcile event"
          query          = "source:kubernetes $kube_namespace"
          tags_execution = "and"
        }
      }

      widget {
        event_stream_definition {
          title          = "Kubernetes rollout events — live stream (ReplicaSet / HelmRelease)"
          query          = "source:kubernetes $kube_namespace"
          event_size     = "s"
          tags_execution = "and"
        }
      }
    }
  }

  # Namespace picker — wired into every widget scope above ($kube_namespace).
  # Default "*" shows all namespaces; pick core-chat to focus on the chat/HPA
  # workloads that drove #1095.
  template_variable {
    name             = "kube_namespace"
    prefix           = "kube_namespace"
    available_values = []
    defaults         = ["*"]
  }
}
