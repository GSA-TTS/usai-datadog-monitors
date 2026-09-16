Per-tenant **Tool Calls** dashboard — individual invocations by tool and model, denials split by
`@reason`, denials by model, a heaviest-requests runaway-loop detector, and a live event stream.
Sourced from the structured `api-beta` application logs (`@event`/`@tool_name`/`@reason`/`@model`),
so no application change was needed. Grouped-row layout matching the Deployments & Rollouts board.
Success rate and latency are deliberately **absent** — there is no tool-completion event and
`@latency_ms` is 0 on all 4357 events measured, so those widgets would read green through a blind
spot. `@conversation_id` is likewise excluded at 5.9% coverage. All gaps are documented in the file
header.
