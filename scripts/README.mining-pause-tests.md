# Mining Pause Tests for Distributed Builds

## Overview

These tests verify that the `compute-workload-monitor` correctly detects build processes and pauses mining operations across the cluster.

## Test Types

### 1. Local Build Test (`test-local-build-mining-pause.sh`)

**Purpose**: Quick test to verify build detection and mining pause on a single host.

**What it tests**:
- ✅ Detects `nix-build` process
- ✅ Pauses mining services (lolminer-nvidia, xmrig)
- ✅ Resumes mining after build completes
- ✅ Shows real-time mining status during build

**Usage**:
```bash
# Run locally on any host with mining enabled
sudo /etc/nixos/scripts/test-local-build-mining-pause.sh
```

**Expected output**:
```
[10:30:15] Initial mining status:
  lolminer-nvidia: running ✓
  xmrig: running ✓

[10:30:20] Building test package...

[T+4s] Mining status:
  lolminer-nvidia: PAUSED ✓
  xmrig: PAUSED ✓

[T+16s] Mining status:
  lolminer-nvidia: PAUSED ✓
  xmrig: PAUSED ✓

[10:30:36] Build completed
✓ lolminer-nvidia resumed
✓ xmrig resumed
```

**Duration**: ~20 seconds

---

### 2. Distributed Build Test (`test-distributed-builds-mining-pause.sh`)

**Purpose**: Comprehensive test to verify mining pause during distributed builds across multiple hosts.

**What it tests**:
- ✅ Coordinator detection (where `nixos-rebuild` runs)
- ✅ Worker detection (remote host receiving build jobs via SSH)
- ✅ Mining pause on both coordinator and worker
- ✅ Mining resume after build completes
- ✅ SSH connectivity and distributed build configuration

**Usage**:
```bash
# From any host (typically zephyr)
sudo /etc/nixos/scripts/test-distributed-builds-mining-pause.sh [coordinator] [worker]

# Default: zephyr as coordinator, nexus as worker
sudo /etc/nixos/scripts/test-distributed-builds-mining-pause.sh

# Custom hosts
sudo /etc/nixos/scripts/test-distributed-builds-mining-pause.sh zephyr forge
```

**Test flow**:
1. Checks connectivity to coordinator and worker
2. Verifies compute-workload-monitor running on both hosts
3. Records initial mining status
4. Creates test package on coordinator
5. Triggers distributed build (coordinator → worker)
6. Monitors mining status on both hosts
7. Verifies mining paused on coordinator
8. Verifies mining paused on worker (may fail - see notes)
9. Waits for build completion
10. Verifies mining resumed on both hosts

**Expected output**:
```
Step 1: Pre-test checks
✓ Coordinator zephyr reachable
✓ Worker nexus reachable
✓ compute-workload-monitor running on zephyr
✓ compute-workload-monitor running on nexus

Step 2: Initial mining status
=== Mining Status on zephyr ===
  lolminer-nvidia: running
  xmrig: running

=== Mining Status on nexus ===
  lolminer-nvidia: running
  xmrig: stopped

Step 3: Triggering distributed build on zephyr
Building test package (distributed to nexus)...

Step 4: Verifying mining pause on coordinator
✓ All mining paused on coordinator zephyr

Step 5: Verifying mining pause on worker
✓ All mining paused on worker nexus

Step 7: Verifying mining resume
=== Mining Status on zephyr ===
  lolminer-nvidia: running
  xmrig: running

✓ SUCCESS: Mining paused on both coordinator and worker
```

**Duration**: ~30 seconds

---

## Important Notes

### Worker Detection Limitation

**Current Implementation**:
- ✅ Detects: `nixos-rebuild`, `colmena`, `nix-build`, `gcc`, `clang`, `cargo`, `cmake`, `make`, `ninja`
- ⚠️ Worker builds via `nix-daemon` SSH protocol may not trigger detection

**Expected behavior**:
- **Coordinator**: ✅ Will pause (detects `nix-build` process)
- **Worker**: ❓ May not pause (no `nix-build` process, only `nix-daemon` child)

**If worker test fails**:
This is expected with current implementation! Workers receive build jobs via SSH from the nix-daemon, not by running `nix-build` directly.

**Solutions if worker detection is needed**:
1. Add `nix-daemon` child process detection
2. Detect high CPU usage from unknown processes
3. Detect SSH connections from build coordinators
4. Use manual build-wrapper scripts for distributed builds

---

## Troubleshooting

### Test fails with "compute-workload-monitor not running"

**Solution**:
```bash
# Enable and start the service
sudo systemctl enable compute-workload-monitor
sudo systemctl start compute-workload-monitor

# Check status
sudo systemctl status compute-workload-monitor
```

### Mining doesn't pause during test

**Possible causes**:
1. compute-workload-monitor not running
2. Mining services not enabled/running
3. Build process too fast (< 2 seconds)
4. Workload type already prioritized (e.g., gaming > builds)

**Debug steps**:
```bash
# Check compute-workload-monitor logs
sudo journalctl -u compute-workload-monitor -f

# Check detected workload
sudo journalctl -u compute-workload-monitor --since "1 minute ago" | grep "Workload"
```

### Mining doesn't resume after test

**Possible causes**:
1. Still in "builds" workload (another build running)
2. Transitioning to "idle" (no auto-start)
3. Service restart required

**Solution**:
```bash
# Check current workload detection
sudo journalctl -u compute-workload-monitor --since "1 minute ago" | grep "Applying profile"

# Manually resume if needed
sudo systemctl start lolminer-nvidia
sudo systemctl start xmrig
```

### Distributed build test: "Cannot reach host"

**Solution**:
```bash
# Test SSH connectivity
ssh zephyr "hostname"
ssh nexus "hostname"

# Check SSH config for build machines
sudo cat /etc/ssh/ssh_config.d/50-build-machines.conf

# Verify distributed builds enabled
nix show-config | grep distributedBuilds
```

---

## Integration with CI/CD

Add to pre-deployment checks:

```bash
#!/bin/bash
# Run mining pause tests before deployment

echo "Testing local build mining pause..."
sudo /etc/nixos/scripts/test-local-build-mining-pause.sh

echo "Testing distributed build mining pause..."
sudo /etc/nixos/scripts/test-distributed-builds-mining-pause.sh zephyr nexus

echo "All tests passed!"
```

---

## Files

- `/etc/nixos/scripts/test-local-build-mining-pause.sh` - Local build test
- `/etc/nixos/scripts/test-distributed-builds-mining-pause.sh` - Distributed build test
- `/etc/nixos/scripts/README.mining-pause-tests.md` - This file

---

## Related Documentation

- `modules/gaming/gaming.nix` - compute-workload-monitor implementation
- `modules/system/distributed-builds.nix` - Distributed build configuration
- `AGENTS.md` - Cluster architecture overview
