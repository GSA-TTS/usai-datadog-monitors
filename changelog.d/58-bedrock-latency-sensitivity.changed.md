Bedrock invocation-latency monitor refit from `>60s over 15m` to `>75s over 30m` (recovery
55s/40s, renotify 60m → 240m) after it kept flapping — measured on gsa over 14 days, the old
config would breach **107 times** versus **30** for the new one, a 72% reduction, while still
catching the 2026-06-02 incident it exists for (which peaks at 86.1s on a 30m average). A 1h
window was rejected because it dilutes that incident below 75s and would miss it entirely.
Dashboard latency markers follow automatically via the shared locals.
