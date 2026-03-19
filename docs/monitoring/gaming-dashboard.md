# Gaming Detection Dashboard

## Import Instructions

1. Open Grafana: http://sentry:3000
2. Navigate to Dashboards → Import
3. Upload `docs/monitoring/gaming-dashboard.json`
4. Click Import

## Panels

- **Current Gaming State**: Shows real-time gaming status per host
- **Gaming Sessions Today**: Time series graph of gaming activity
- **Detection Method Distribution**: Pie chart showing GameMode vs GPU fallback usage

## Queries

```promql
# Current state
gaming_active

# Sessions today
gaming_active

# By detection method
count by (detection_method) (gaming_active == 1)
```

## Testing

To test with live gaming:
1. Start a game with GameMode support
2. Verify dashboard shows "🎮 Gaming" for that host
3. Close game and verify state returns to "No Gaming"
