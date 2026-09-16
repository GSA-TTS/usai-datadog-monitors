SCIM provisioning monitors now alert on the **401 rate** (`> 50%` over 24h) instead of a raw 401
count (`> 0`). Under the OAuth2 client-credentials grant a healthy realm emits periodic bursts of
401s each time its hourly access token expires, so the count form paged daily for realms that were
working — `ed` measured 38 × 401 against 14,661 × 200 (0.26%) while genuinely-broken `ntsb` measured
100%. Also pins the dashboard's SCIM widgets to a 24h window so they stop contradicting the
monitors, which evaluate over `last("1d")`.
