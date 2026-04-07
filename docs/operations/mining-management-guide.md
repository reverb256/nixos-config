# Mining Management for Provider

## Overview



## Quick Reference

```bash
# Show current status

# Stop all mining (show full GPU capacity)

# Resume mining
```

## GPU Capacity States

| State | Mining Status | NVIDIA GPUs Available | AMD GPUs Available | Use Case |
|-------|--------------|---------------------|-------------------|----------|
| **Mining Stopped** | Stopped | 4-5 NVIDIA GPUs | 3 AMD GPUs (Forge) | Active bidding on large GPU leases |

**Note**: You have **8 total GPUs** (5 NVIDIA + 3 AMD):
- **NVIDIA GPUs**: 5 total (Forge: 2, Nexus: 1, Zephyr: 2)
- **AMD GPUs**: 3 total (Forge: 2, Sentry: 1)
- **Provider**: Only counts NVIDIA GPUs (5-6 depending on counting method)

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

- **Stop mining manually** - To show full capacity in provider inventory
- **Trade-off**: Lost mining revenue vs. attracting larger leases
- **Recommendation**: Keep mining running unless actively seeking large GPU leases
