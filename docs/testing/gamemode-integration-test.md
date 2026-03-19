# GameMode Detection Integration Test

**Date:** 2026-03-19
**Host:** zephyr (test host)

## Pre-Test Checklist

- [x] GameMode package installed
- [x] compute-workload-monitor configured
- [x] nix flake check passed
- [ ] System deployed with `just deploy`

## Test Procedure

### 1. Verify GameMode Installed

```bash
ssh zephyr "which gamemoded"
```

Expected: `/run/current-system/sw/bin/gamemoded`

### 2. Test Detection Function

```bash
ssh zephyr "bash -c 'source /etc/nixos/modules/system/compute-workload-monitor.nix 2>/dev/null || true; detect_gaming_gamemode; echo \"Exit code: \$?\"'"
```

Expected: Exit code 2 (GameMode installed but not running)

### 3. Start GameMode Daemon

```bash
ssh zephyr "systemctl start gamemoded"
ssh zephyr "systemctl status gamemoded"
```

Expected: Daemon active (running)

### 4. Test Gaming Detection

Start a test game (or use `gamemoderun` with a simple application):

```bash
ssh zephyr "gamemoderun glxgears"
```

In another terminal, check logs:

```bash
ssh zephyr "journalctl -u compute-workload-monitor -f | grep -E 'Gaming|lolminer'"
```

Expected within 10 seconds:
- "Gaming STARTED (detected by gamemode)"
- "Pausing lolminer-nvidia"
- "lolminer-nvidia stopped"

### 5. Verify lolminer Paused

```bash
ssh zephyr "systemctl status lolminer-nvidia"
```

Expected: `inactive (dead)`

### 6. Check State File

```bash
ssh zephyr "cat /run/compute-workload-monitor/gaming_state"
```

Expected:
```
LAST_CHECK=<timestamp>
GAMING_ACTIVE=1
DETECTION_METHOD=gamemode
HYSTERESIS_COUNT=0
PAUSE_COUNT=1
```

### 7. Check Prometheus Metric

```bash
curl -s http://zephyr:9090/api/v1/query?query=gaming_active{host=\"zephyr\"} | jq
```

Expected: `gaming_active{host="zephyr",detection_method="gamemode"} 1`

### 8. Stop Game and Verify Resume

Stop the game (Ctrl+C in glxgears), wait 20 seconds, then:

```bash
ssh zephyr "systemctl status lolminer-nvidia"
ssh zephyr "cat /run/compute-workload-monitor/gaming_state"
```

Expected: lolminer active, `GAMING_ACTIVE=0`

## Test Results

- [ ] GameMode installed
- [ ] Gaming detected within 10s
- [ ] lolminer paused immediately
- [ ] State file updated
- [ ] Prometheus metric exported
- [ ] lolminer resumed after ~15s
- [ ] No rapid pause/resume cycling

## Issues Found

[Document any issues encountered]
