# Gaming Detection & Automatic Mining Pause

## Overview

When you start a game, the system automatically pauses mining on that
host to free GPU resources for gaming. Mining resumes automatically
after you close the game (~15 second delay to prevent rapid cycling).

## How It Works

1. **Game starts** → GameMode daemon activates (or GPU pattern detected)
2. **Detected within 10 seconds** → lolminer paused
3. **Game closes** → 15-second countdown begins (3 checks at 5s intervals)
4. **Countdown complete** → lolminer resumes

## Detection Methods

### Primary: GameMode
- Steam games (most modern titles)
- Lutris games
- Heroic games
- Native Linux games with GameMode support

### Fallback: GPU Pattern
- Games without GameMode support
- Older games
- GPU-intensive applications

## Monitoring

### Systems Intelligence Plasmoid
- 🎮 icon shows when gaming detected
- Mining section updates in real-time
- Per-host gaming status

### Grafana Dashboard
- Dashboard: "Gaming Detection"
- Panels:
  - Current gaming state per host
  - Gaming sessions over time
  - Detection method distribution

### Prometheus Queries
```promql
# Current gaming state
gaming_active

# Gaming by host
count by (host) (gaming_active == 1)

# Gaming sessions today
increase(gaming_active[1d])
```

## Manual Control

### Pause Mining Manually
```bash
systemctl stop lolminer-nvidia
```

### Resume Mining Manually
```bash
systemctl start lolminer-nvidia
```

### Check Gaming Detection Status
```bash
cat /run/compute-workload-monitor/gaming_state
```

### View Detection Logs
```bash
journalctl -u compute-workload-monitor -f | grep gaming
```

## Troubleshooting

### Gaming Not Detected

1. **Check GameMode is running:**
   ```bash
   systemctl status gamemoded
   ```

2. **Verify game supports GameMode:**
   ```bash
   gamemoded -s  # Run while game is active
   # Should return 1
   ```

3. **Check GPU fallback:**
   ```bash
   journalctl -u compute-workload-monitor -n 50 | grep "GPU pattern"
   ```

### Mining Not Resuming

1. **Check hysteresis countdown:**
   ```bash
   cat /run/compute-workload-monitor/gaming_state | grep HYSTERESIS_COUNT
   # Should reach 0 before resume
   ```

2. **Manually resume if stuck:**
   ```bash
   systemctl start lolminer-nvidia
   # Reset countdown
   echo "HYSTERESIS_COUNT=0" >> /run/compute-workload-monitor/gaming_state
   ```

### False Positives

Rare, but can occur with non-game GPU workloads (video rendering,
AI inference). Monitor logs and consider manual management for these
workloads.

## Technical Details

### Detection Hierarchy
1. GameMode daemon (authoritative, fast)
2. GPU pattern analysis (fallback, slower)

### Hysteresis
- 3 consecutive checks at 5-second intervals
- Total delay: ~15 seconds
- Prevents rapid cycling during game loading/menus

### State File
- Location: `/run/compute-workload-monitor/gaming_state`
- Contents: Current state, detection method, countdown, pause count
- Persists across service restarts

### Metrics
- Exported to: `/var/lib/prometheus/node-exporter/textfile-collector/gaming.prom`
- Scraped by: Prometheus every 15 seconds
- Available in: Grafana and plasmoid

## Performance Impact

- Gaming detection: <10 seconds
- Mining revenue lost: ~15 seconds per session
- System overhead: Negligible (one extra Prometheus query per cycle)

## Future Enhancements

- Per-GPU detection (multi-GPU hosts)
- Gaming session analytics
- Automatic overclocking resume
- Discord/webhook notifications
