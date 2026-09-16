Per-tenant **Tool Calls** dashboard — individual tool invocations, denials with `@reason`, and
which models drive tool use, sourced from the structured `api-beta` application logs
(`@event`/`@tool_name`/`@reason`/`@model`). Grouped-row layout matching the Deployments & Rollouts
board. Success rate and latency are deliberately **absent**: there is no tool-completion event and
`@latency_ms` is 0 on all 4357 events measured, so those widgets would read green through a blind
spot. Both gaps are documented in the file header and in the on-board notes.
