# Mining Management for Provider

> **Status:** Historical proposal / incomplete reference
> **Last Verified:** 2026-08-09 (classification only; runtime procedures not verified)
> **Source:** `hosts/*/peakminer.nix`, `modules/services/peakminer.nix`, and the live host services
>
> This document is not an executable runbook. Its blank command examples and capacity
> figures are retained as historical context. Use the declared Nix configuration and
> guarded host controls when changing mining state.

## Overview

Mining and provider availability compete for GPU capacity. The current product-name
identity and per-GPU settings live in each host's `peakminer.nix`; do not infer current
inventory from this historical document.

## Quick Reference

Use source-backed commands for current state:

```bash
just status
just health
rg -n 'peakminer|gpuName|instances' hosts/*/peakminer.nix modules/services/peakminer.nix
```

## GPU Capacity States

| State | Mining Status | NVIDIA GPUs Available | AMD GPUs Available | Use Case |
|-------|--------------|---------------------|-------------------|----------|
| **Mining Stopped** | Stopped | 4-5 NVIDIA GPUs | 3 AMD GPUs (Forge) | Active bidding on large GPU leases |

The GPU counts below are historical figures from the original proposal. Verify
current inventory from the host configuration and live GPU discovery before using
them.

## When to Use Each Mode

### Keep Mining Running (Default)
- **When**: Most of the time
- **Why**: Generate mining revenue when GPUs are idle
- **Drawback**: Provider only sees 1-2 GPUs as available

### Stop Mining Temporarily
- **When**: Expecting high-value GPU leases, testing provider, or troubleshooting
- **Why**: Show full 4-5 GPU capacity to attract larger bids
- **Benefit**: Provider can bid on larger GPU leases
- **Drawback**: Lost mining revenue while stopped

## Preemption Still Works

- Mining: 100M (preemptible-mining)

The provider's inventory display is informational - Kubernetes scheduler handles actual preemption.

## Example Workflow

```bash
# 1. Check current status
# Output: 6 running, 2 GPUs available

# 2. Stop mining to show full capacity
# Output: 6 stopped, 4 GPUs available

# (provider can now bid on larger GPU deployments)

# 4. Resume mining
# Output: 6 running, 1-2 GPUs available
```

## Monitoring GPU Usage

```bash
# Check what's using GPUs
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu") | "\(.metadata.namespace)/\(.metadata.name)"'

# Check provider inventory
kubectl logs -n default default-default-fixed-0 --tail=5 | grep "total_available"
```

## Automated Approach (Future)

To automate this, you could:
1. Schedule mining stops during peak bidding hours
2. Integrate with provider bidding activity
3. Use Kubernetes CronJobs to periodically stop/start mining
4. Monitor provider order queue and stop mining when orders appear

## Files

- **This Doc**: `/etc/nixos/docs/operations/mining-management-guide.md`
- **Priority Update**: `/etc/nixos/docs/operations/mining-priority-update-2026-03-21.md`

## Summary

- Use the host's declared mining controls rather than blank commands in this file.
- Treat provider inventory as runtime state; verify it before making scheduling decisions.
- Preserve the mining/provider trade-off described here as historical context until a
  source-backed operational runbook is written.
