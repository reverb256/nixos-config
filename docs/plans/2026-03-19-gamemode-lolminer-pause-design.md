# GameMode-Based Gaming Detection for Selective lolminer Pause

**Date:** 2026-03-19
**Status:** Design Approved
**Complexity:** Low (~150 lines)
**Risk:** Low (per-host decisions, isolated changes)

## Problem Statement

Current `compute-workload-monitor` only pauses lolminer on nexus when gaming is detected, using an incomplete game process list. User wants:

1. Pause lolminer-nvidia on **the specific host where gaming is detected**
2. Don't affect mining on other hosts without games
3. Eliminate manual game process list maintenance
4. Add monitoring visibility into gaming sessions

## Solution Overview

Use GameMode daemon as authoritative gaming detection source with GPU pattern fallback. Each host makes independent pause/resume decisions based on local gaming state. Export gaming state to Prometheus for cluster-wide visibility.

### Detection Hierarchy

1. **Primary:** GameMode daemon (`gamemoded -s`) → returns 1 if gaming, 0 if not
2. **Fallback:** GPU pattern analysis if GameMode unavailable
3. **Local Decision:** Pause/resume lolminer-nvidia on local host only
4. **Prometheus Export:** Push `gaming_active` metric to node_exporter textfile collector

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  compute-workload-monitor (per-host daemon, 5s polling)     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. detect_gaming_gamemode()                                │
│     ├─ Query gamemoded -s                                   │
│     └─ Fallback to GPU pattern if unavailable               │
│                                                              │
│  2. Read /tmp/gaming-state (previous state)                 │
│                                                              │
│  3. Compare current vs previous state                       │
│     ├─ 0→1: Pause lolminer immediately                      │
│     ├─ 1→0: Start 3-check hysteresis countdown             │
│     └─ Unchanged: Update countdown if in progress           │
│                                                              │
│  4. If countdown reaches 0: Resume lolminer                 │
│                                                              │
│  5. Update /tmp/gaming-state                                │
│                                                              │
│  6. Export metric to node_exporter                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Modified: `modules/system/compute-workload-monitor.nix`

**New Functions:**

**`detect_gaming_gamemode()`**
```bash
# Returns: 1 if gaming active, 0 if not
# Primary: gamemoded -s
# Fallback: GPU pattern analysis
```

**`export_gaming_metric()`**
```bash
# Write to: /var/lib/node_exporter/textfile_collector/gaming.prom
# Format: gaming_active{host="zephyr"} 1
```

**`manage_lolminer_for_gaming()`**
```bash
# Orchestration function
# Calls detection, manages pause/resume with hysteresis
# Exports metrics each cycle
```

### 2. State Tracking

**File:** `/tmp/gaming-state`

**Format:**
```bash
LAST_CHECK=1710912345
GAMING_ACTIVE=1
DETECTION_METHOD=gamemode
HYSTERESIS_COUNT=2  # 0-3, resume when reaches 0
PAUSE_COUNT=5       # Total pause events this session
```

### 3. Prometheus Integration

**Method:** node_exporter textfile collector (already running)

**File:** `/var/lib/node_exporter/textfile_collector/gaming.prom`

**Format:**
```prometheus
# HELP gaming_active Whether a game is currently running (1=yes, 0=no)
# TYPE gaming_active gauge
gaming_active{host="zephyr",detection_method="gamemode"} 1
```

**Benefits:**
- No pushgateway required
- Automatically scraped every 15s
- Shows in Systems Intelligence plasmoid
- Historical tracking in Grafana

## Data Flow

### Gaming Detection Flow

```
Game starts
  ↓
GameMode daemon activated by game
  ↓
compute-workload-monitor polls (5s)
  ↓
detect_gaming_gamemode() returns 1
  ↓
Compare with /tmp/gaming-state (0)
  ↓
State changed 0→1: Pause lolminer immediately
  ↓
systemctl stop lolminer-nvidia
  ↓
Update /tmp/gaming-state (GAMING_ACTIVE=1)
  ↓
Export metric to node_exporter
```

### Gaming Resume Flow (Hysteresis)

```
Game closes
  ↓
GameMode daemon deactivated
  ↓
compute-workload-monitor polls (5s)
  ↓
detect_gaming_gamemode() returns 0
  ↓
Compare with /tmp/gaming-state (1)
  ↓
State changed 1→0: Set HYSTERESIS_COUNT=3
  ↓
Export metric (gaming_active=1 still)
  ↓
[Next poll] HYSTERESIS_COUNT=2 (still gaming, no resume)
  ↓
[Next poll] HYSTERESIS_COUNT=1 (still gaming, no resume)
  ↓
[Next poll] HYSTERESIS_COUNT=0
  ↓
Resume lolminer
  ↓
systemctl start lolminer-nvidia
  ↓
Update /tmp/gaming-state (GAMING_ACTIVE=0)
  ↓
Export metric (gaming_active=0)
```

**Total delay:** ~15 seconds (3 checks × 5s interval)

### GPU Fallback Flow

```
GameMode unavailable (not installed or daemon dead)
  ↓
detect_gaming_gamemode() falls back to detect_gpu_pattern()
  ↓
Analyze nvidia-smi utilization over last 30s
  ↓
Variable utilization (stddev > 15%) → Gaming detected
  ↓
Steady utilization (stddev < 10%) → Mining/other
  ↓
Proceed with pause/resume logic same as GameMode path
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| GameMode not installed | Log warning, use GPU fallback |
| GameMode daemon not running | Log warning, use GPU fallback |
| node_exporter directory missing | Create directory, log error |
| lolminer stop fails | Log systemctl status, retry next cycle |
| lolminer start fails | Log systemctl status, retry next cycle |
| Invalid/corrupt state file | Regenerate with defaults, log incident |
| GPU query fails (no NVIDIA GPU) | Log warning, assume no gaming |

**Service Resilience:**
- Never crash on errors
- Log all incidents for debugging
- Retry transient failures on next cycle
- Graceful degradation (GameMode → GPU → assume no gaming)

## Testing Strategy

### Unit Testing

1. **GameMode Detection**
   - Mock `gamemoded -s` returning 0 and 1
   - Verify function returns correct values
   - Test fallback to GPU pattern

2. **GPU Pattern Detection**
   - Feed synthetic nvidia-smi data (variable vs steady)
   - Verify correct classification
   - Test edge cases (0% util, 100% util)

3. **Hysteresis Logic**
   - Test state transition 0→1 (immediate pause)
   - Test state transition 1→0 (3-check countdown)
   - Test countdown persistence across cycles

### Integration Testing

1. **Game Start Detection**
   - Launch actual game via Steam
   - Verify lolminer stops within 10 seconds
   - Check metric shows `gaming_active=1`

2. **Game Resume Detection**
   - Close game
   - Verify lolminer resumes after ~15 seconds
   - Check metric shows `gaming_active=0`

3. **GPU Fallback**
   - Stop gamemoded daemon
   - Launch GPU-intensive game
   - Verify lolminer stops using GPU detection

4. **Prometheus Integration**
   - Check metric appears in node_exporter
   - Query via Prometheus: `gaming_active{host="zephyr"}`
   - Verify Systems Intelligence plasmoid shows data

### Edge Cases

- **Game crashes:** lolminer resumes after hysteresis
- **Rapid game start/stop:** Hysteresis prevents rapid cycling
- **Multiple games:** Each treated as single gaming session
- **Game with no GameMode support:** GPU fallback catches it
- **No gaming detected:** lolminer continues normally

## Implementation Plan

### Phase 1: Core Detection (Priority 1)
- [ ] Add `gamemode` package to compute nodes
- [ ] Implement `detect_gaming_gamemode()` function
- [ ] Implement `export_gaming_metric()` function
- [ ] Test GameMode detection with actual game

### Phase 2: Hysteresis & State (Priority 1)
- [ ] Implement `/tmp/gaming-state` file handling
- [ ] Implement hysteresis countdown logic
- [ ] Modify main loop to call gaming detection
- [ ] Test pause/resume cycles

### Phase 3: GPU Fallback (Priority 2)
- [ ] Implement `detect_gpu_pattern()` function
- [ ] Add utilization history tracking (30s window)
- [ ] Test fallback when gamemoded stopped
- [ ] Validate with non-GameMode game

### Phase 4: Integration & Polish (Priority 2)
- [ ] Add to Systems Intelligence plasmoid
- [ ] Create Grafana dashboard panel
- [ ] Document gaming session tracking
- [ ] Update cluster documentation

## Dependencies

**Required Packages:**
- `gamemode` - GameMode daemon and libraries

**Existing Dependencies (No Change):**
- `node_exporter` - Already running on all hosts
- `nvidia-smi` - Already present for NVIDIA GPU monitoring

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| GameMode not supported by some games | Medium | GPU fallback catches unsupported games |
| False positive (non-game GPU workload) | Low | Low mining revenue loss, acceptable |
| False negative (gaming not detected) | Low | User can manually pause, rare with GameMode |
| Service crashes | Low | Comprehensive error handling, systemd restart |
| Rapid pause/resume cycling | Low | Hysteresis prevents cycling |

**Overall Risk:** LOW

- Changes isolated to one service
- Per-host decisions (no cluster coordination)
- Graceful degradation (GameMode → GPU → assume no gaming)
- Easy rollback (git revert)

## Rollback Plan

If issues arise:

1. **Immediate:** Revert commit to `compute-workload-monitor.nix`
2. **Service:** `systemctl restart compute-workload-monitor`
3. **Verification:** Check lolminer running normally

**No configuration changes required** - rollback is pure code revert.

## Success Criteria

✅ Gaming detected within 10 seconds of game start
✅ lolminer paused on gaming host only
✅ Other hosts continue mining unaffected
✅ lolminer resumes ~15 seconds after game closes
✅ No rapid pause/resume cycling
✅ Gaming state visible in Prometheus/Grafana
✅ Systems Intelligence plasmoid shows gaming sessions

## Future Enhancements (Out of Scope)

- Per-GPU detection (multi-GPU hosts)
- Gaming session analytics (total time, favorite games)
- Automatic lolminer overclocking resume
- Integration with Discord/webhook notifications
- Machine learning for GPU pattern classification

## References

- **GameMode Documentation:** https://github.com/FeralInteractive/gamemode
- **node_exporter Textfile Collector:** https://github.com/prometheus/node_exporter#textfile-collector
- **Existing Module:** `modules/system/compute-workload-monitor.nix`
- **Related Issue:** User request for per-host gaming detection

---

**End of Design Document**
