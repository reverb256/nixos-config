# Akash Provider - Quick Status

**Last Updated**: 2026-03-20 08:24 UTC

## 🎯 Summary

| Metric | Value |
|--------|-------|
| Status | 🟡 **RUNNING - AWAITING VERIFICATION** |
| Uptime | 2h 45m |
| CPU Usage | 94.1% (expected - processing orders) |
| Active Leases | 0 (blocked by verification) |
| Orders Processed | Continuously (all rejected) |

## 📋 Verification Status

**❌ NOT VERIFIED** - Attributes need x63 auditor signature

**Next Step**: Contact `@andy01` on [Akash Discord](https://discord.gg/akash)

```
Provider Address: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
Hostname: provider.provider.reverb256.ca
```

## 🖥️ Resources

| Node | CPU | GPU | RAM | Storage |
|------|-----|-----|-----|---------|
| forge | 6 | 2 | 13GB | 206GB |
| nexus | 24 | 1 | 38GB | 823GB |
| sentry | 16 | 0 | 26GB | 206GB |
| zephyr | 32 | 2 | 28GB | 837GB |
| **Total** | **78** | **5** | **111GB** | **2TB+** |

## 📈 Pricing

```
CPU:     0.004 uakt/mCPU/s
Memory:  0.0016 uakt/MB/s
Storage: 0.00016 uakt/MB/s
IP:      60 uakt/IP/s
```

## 🚀 Quick Commands

```bash
# Status
ssh zephyr "kubectl get pods -n akash-services | grep provider"

# Logs
ssh zephyr "kubectl logs -n akash-services akash-provider-akash-provider-fixed-0 --tail=50"

# JSON Status
ssh zephyr "kubectl exec -n akash-services akash-provider-akash-provider-fixed-0 -- curl -sk https://localhost:8443/status | jq ."

# Verification Errors
ssh zephyr "kubectl logs -n akash-services akash-provider-akash-provider-fixed-0 2>&1 | grep 'attribute signature' | wc -l"
```

## 📝 Notes

- Provider is v0.10.7-v12 (latest)
- All nodes detected correctly
- Bid pricing strategy configured
- DNS configured (provider.provider.reverb256.ca)
- TLS certificate active

**See [akash-provider-verification.md](./akash-provider-verification.md) for detailed verification steps.**
