# Gaming Detection Deployment Guide

## Pre-Deployment Checklist

- [ ] All code reviewed and approved
- [ ] nix flake check passed
- [ ] Documentation complete
- [ ] Backup current configuration

## Deployment Targets

- zephyr (control plane, gaming, AI)
- nexus (storage, GPU computing)
- forge (GPU computing, mining)

## Deployment Steps

### 1. Pre-Deployment Validation

```bash
cd /etc/nixos
nix flake check
```

### 2. Review Changes

```bash
git diff main..HEAD --stat
git log --oneline main..HEAD
```

### 3. Deploy to All Compute Nodes

```bash
just deploy
```

This will build and switch configurations on all hosts.

### 4. Verify Services Running

```bash
for host in zephyr nexus forge; do
  echo "=== $host ==="
  ssh $host "systemctl status compute-workload-monitor | head -3"
  ssh $host "systemctl status lolminer-nvidia | head -3"
done
```

Expected: All services active on all hosts.

### 5. Verify GameMode Available

```bash
for host in zephyr nexus forge; do
  echo "=== $host ==="
  ssh $host "which gamemoded && gamemoded -v"
done
```

Expected: GameMode installed on all hosts.

### 6. Check for Errors

```bash
for host in zephyr nexus forge; do
  echo "=== $host ==="
  ssh $host "journalctl -u compute-workload-monitor -n 20 --no-pager"
done
```

Expected: No errors, clean startup.

### 7. Test Per-Host Independence

1. Start game on zephyr only
2. Check mining status:

```bash
for host in zephyr nexus forge; do
  echo "=== $host ==="
  ssh $host "systemctl is-active lolminer-nvidia"
done
```

Expected: zephyr=inactive, nexus=active, forge=active

### 8. Verify Prometheus Metrics

```bash
curl -s 'http://sentry:9090/api/v1/query?query=gaming_active' | jq
```

Expected: Metrics from all 3 compute hosts.

## Rollback Procedure

If issues occur:

```bash
# On affected host
just switch  # Rolls back to previous configuration

# Or rollback specific commit
git revert <commit-sha>
just deploy
```

## Deployment Complete

- [ ] All 3 compute nodes deployed
- [ ] Services running on all hosts
- [ ] GameMode available on all hosts
- [ ] Per-host independence verified
- [ ] Metrics from all hosts
