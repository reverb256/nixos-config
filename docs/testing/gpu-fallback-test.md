# GPU Fallback Detection Test

**Date:** 2026-03-19
**Host:** zephyr (test host)

## Purpose

Verify GPU pattern fallback works when GameMode is unavailable.

## Test Procedure

### 1. Stop GameMode Daemon

```bash
ssh zephyr "systemctl stop gamemoded"
ssh zephyr "systemctl status gamemoded"
```

Expected: Daemon inactive (dead)

### 2. Monitor Detection Logs

```bash
ssh zephyr "journalctl -u compute-workload-monitor -f | grep -E 'GPU pattern|gaming'"
```

### 3. Start GPU-Intensive Game

Use a game or application that:
- Uses GPU heavily (>80% utilization)
- Has variable load (gaming, not mining)

Example:
```bash
ssh zephyr "gamemoderun glxgears"
```

### 4. Verify GPU Pattern Detection

Wait 30 seconds for utilization history to build.

Expected in logs:
- "GameMode unavailable, using GPU pattern detection"
- "GPU pattern: Gaming detected (util=XX%, variance=YY%)"

### 5. Verify lolminer Paused

```bash
ssh zephyr "systemctl status lolminer-nvidia"
```

Expected: inactive

### 6. Check Detection Method

```bash
ssh zephyr "cat /run/compute-workload-monitor/gaming_state"
```

Expected: `DETECTION_METHOD=gpu_fallback`

### 7. Stop Game and Verify Resume

Stop the game, wait 20 seconds:

```bash
ssh zephyr "systemctl status lolminer-nvidia"
ssh zephyr "cat /run/compute-workload-monitor/gaming_state"
```

Expected: lolminer active, GAMING_ACTIVE=0

### 8. Restart GameMode

```bash
ssh zephyr "systemctl start gamemoded"
```

### 9. Verify Switch Back to GameMode

Start game again:

```bash
ssh zephyr "journalctl -u compute-workload-monitor -f | grep gaming"
```

Expected: "GameMode: Gaming detected" (not GPU pattern)

## Test Results

- [ ] GPU fallback works when GameMode unavailable
- [ ] ~30s detection delay acceptable
- [ ] Switches back to GameMode when available
- [ ] Hysteresis works with GPU detection too

## Edge Cases Tested

- [ ] Rapid start/stop (hysteresis validation)
- [ ] Game crash (graceful resume)
- [ ] Multiple games sequentially
- [ ] Non-game GPU workload (false positive check)
