# System Modules

This directory contains core system-level modules for the NixOS cluster.

## Modules

### Compute Workload Monitor

The `compute-workload-monitor` service provides intelligent GPU workload
detection and automatic mining pause/resume functionality.

#### Features

- **Gaming Detection:** Automatically pauses lolminer when gaming detected
- **GPU Pattern Analysis:** Fallback detection for games without GameMode
- **Hysteresis:** 15-second countdown prevents rapid cycling
- **Prometheus Metrics:** Exports gaming state for monitoring
- **State Tracking:** Persistent state file for debugging

#### Gaming Detection

The compute-workload-monitor automatically pauses lolminer when gaming
is detected on the local host.

##### Detection Methods

1. **GameMode (Primary):** Queries `gamemoded -s` for authoritative
   gaming detection. Returns 1 if gaming active, 0 if not.

2. **GPU Pattern (Fallback):** Analyzes GPU utilization variability.
   Gaming = variable utilization (>15% change), Mining = steady (<5%).

##### Pause/Resume Logic

- **Pause:** Immediate when gaming detected
- **Resume:** After 3 consecutive checks (~15s hysteresis)
- **State:** Tracked in `/run/compute-workload-monitor/gaming_state`

##### Prometheus Metrics

Exports `gaming_active{host="zephyr",detection_method="gamemode"}` metric
via node_exporter textfile collector.

##### Configuration

No configuration required. Automatically enabled on hosts with:
- GameMode package installed
- NVIDIA GPU
- lolminer service running

##### State File Format

Location: `/run/compute-workload-monitor/gaming_state`

```bash
LAST_CHECK=1710912345
GAMING_ACTIVE=1
DETECTION_METHOD=gamemode
HYSTERESIS_COUNT=0
PAUSE_COUNT=5
```

##### Functions

- `detect_gaming()`: Unified gaming detection (GameMode → GPU fallback)
- `detect_gaming_gamemode()`: GameMode daemon query
- `detect_gpu_pattern()`: GPU utilization pattern analysis
- `manage_lolminer_for_gaming()`: Pause/resume orchestration with hysteresis
- `export_gaming_metric()`: Prometheus metric export

#### Usage

The service runs automatically on hosts where it's enabled. No manual
configuration required.

See `docs/features/gaming-detection.md` for complete user guide including
troubleshooting and manual control.

## Adding New Modules

1. Create module directory: `mkdir modules/system/my-module`
2. Add `default.nix` with module configuration
3. Import in `modules/default.nix`:
   ```nix
   system = {
     my-module = import ./system/my-module;
   };
   ```

## Module Conventions

- Use `lib.mkOptionDefault` for extensible options
- Follow 2-space indentation
- Add comprehensive documentation
- Include Prometheus metrics where applicable
- Support graceful degradation

---

**Last Updated:** 2026-03-19
