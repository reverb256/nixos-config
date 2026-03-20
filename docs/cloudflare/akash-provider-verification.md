# Akash Provider Verification Guide

## Provider Information

### Identity
| Field | Value |
|-------|-------|
| **Provider Address** | `akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6` |
| **Public Hostname** | `provider.provider.reverb256.ca` |
| **Version** | `v0.10.7-v12` |
| **Chain ID** | `akashnet-2` |

### Capacity
| Resource | Total Available |
|----------|-----------------|
| CPU | 78 cores |
| GPU | 5 GPUs (2x forge, 1x nexus, 2x zephyr) |
| Memory | 111 GB |
| Storage | 2+ TB |

### Pricing Strategy
| Attribute | Multiplier |
|-----------|------------|
| CPU | 0.004 uakt per mCPU per second |
| Memory | 0.0016 uakt per MB per second |
| Storage | 0.00016 uakt per MB per second |
| IP | 60 uakt per IP per second |

### Configuration
```bash
AKASH_CLUSTER_PUBLIC_HOSTNAME=provider.provider.reverb256.ca
AKASH_DEPLOYMENT_INGRESS_DOMAIN=ingress.provider.reverb256.ca
AKASH_BID_DEPOSIT=750000 uakt
AKASH_GAS_PRICES=0.025 uakt
```

---

## Verification Process

### Current Status: ⚠️ NOT VERIFIED

**Error**: `attribute signature requirements not met`

The provider is actively fetching and evaluating orders but cannot place bids because the provider attributes have not been signed by an x63 auditor.

### Steps to Get Verified

1. **Join Akash Discord**
   - Go to: https://discord.gg/akash
   - Verify your account

2. **Contact x63 Auditor**
   - Find user `@andy01` in the Akash Discord
   - Send a message with the following format:

   ```
   Hi @andy01,

   I'd like to get my provider attributes verified.

   Provider Address: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
   Public Hostname: provider.provider.reverb256.ca
   Chain: akashnet-2
   Capacity: 78 cores, 5 GPUs, 111GB RAM, 2TB+ storage

   My provider is running and actively processing orders but
   needs auditor signatures to bid.

   Thanks!
   ```

3. **Provide Additional Information if Requested**
   - Proof of ownership (wallet signature)
   - Provider uptime stats
   - Hardware specifications
   - Network topology

4. **Wait for Signature**
   - The auditor will verify your provider
   - Once signed, bids will be accepted automatically

5. **Verify Success**
   ```bash
   # Check logs for successful bids
   ssh zephyr "kubectl logs -n akash-services akash-provider-akash-provider-fixed-0 --tail=100 | grep -i 'bid placed'"

   # Check active leases
   ssh zephyr "curl -sk https://localhost:8443/status | jq '.cluster.leases'"
   ```

---

## Monitoring Commands

### Check Provider Status
```bash
ssh zephyr "kubectl exec -n akash-services akash-provider-akash-provider-fixed-0 -- /bin/sh -c 'curl -sk https://localhost:8443/status | jq .'"
```

### Check Recent Logs
```bash
ssh zephyr "kubectl logs -n akash-services akash-provider-akash-provider-fixed-0 --since=10m | tail -50"
```

### Check CPU Usage
```bash
ssh zephyr "kubectl exec -n akash-services akash-provider-akash-provider-fixed-0 -- /bin/sh -c 'ps aux | grep provider'"
```

### Check for Bid Errors
```bash
ssh zephyr "kubectl logs -n akash-services akash-provider-akash-provider-fixed-0 2>&1 | grep -i 'attribute\|signature' | tail -20"
```

---

## Expected Behavior After Verification

### Before Verification
- Provider fetches orders continuously
- All bids fail with "attribute signature requirements not met"
- CPU usage: ~90-95% (processing orders but can't bid)
- Active leases: 0

### After Verification
- Provider fetches orders continuously
- Bids are placed successfully
- CPU usage: ~40-70% (varies with order volume)
- Active leases: increases as deployments win bids
- Revenue begins accumulating

---

## Troubleshooting

### High CPU Usage (94%)
**This is expected before verification.** The provider is processing orders it can't bid on. Once verified, the same CPU usage will produce active bids.

### No Active Leases
Normal until verification is complete. After verification:
1. Monitor `https://cloudmos.io` for your provider
2. Check provider leaderboard on Akash Console
3. Bids should appear within minutes of auditor signature

### "Attribute signature requirements not met" persists
1. Confirm the auditor signed your attributes
2. Check you're using the correct provider address
3. Restart the provider:
   ```bash
   ssh zephyr "kubectl rollout restart statefulset/akash-provider-akash-provider-fixed -n akash-services"
   ```

---

## References

- **Akash Docs**: https://docs.akash.network
- **Provider Setup**: https://docs.akash.network/providers
- **x63 Audit Program**: https://x63.io
- **Cloudmos**: https://cloudmos.io (monitor your provider)
- **Big Dipper**: https://big-dipper.akash.bigdipper.live (explorer)

---

**Last Updated**: 2026-03-20
**Provider Version**: v0.10.7-v12
