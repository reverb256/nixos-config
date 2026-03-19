# Akash Provider Troubleshooting Summary - 2026-03-19 22:35

## Error That Persists
```
Error: client is not running. Use .Start() method to start
```
**Module**: bidengine-service
**Exit Code**: 1
**Status**: CrashLoopBackOff

## What We've Tried

### ✅ Fixed Issues
1. **RBAC Permissions**: Added PersistentVolume and StorageClass permissions
2. **Pricing Script**: Fixed invalid base64 data in ConfigMap
3. **Certificate Issuer**: Disabled (AP_CERT_ISSUER_ENABLED=false)
4. **Bid Pricing Scale Parameters**: Added missing scale configuration
   - bidpricecpuscale: 0.004
   - bidpricememoryscale: 0.0016
   - bidpriceendpointscale: 1
   - bidpriceipscale: 60
   - bidpricestoragescale: 0.00016,beta2=0.00016,beta3=0.00016,ram=0.00016

### ❌ Still Failing
- Bidengine-service initialization
- Tried both `scale` and `shellScript` pricing strategies
- Error occurs after successful provider attributes fetch

## Configuration Details

**Helm Chart**: provider-14.0.8
**App Version**: 0.10.7
**Provider Address**: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
**Certificate**: Valid on-chain (serial: 189E1B2C59B6BFF3)

**Environment Variables**:
- AKASH_FROM: provider-wallet
- AP_CERT_ISSUER_ENABLED: false
- AKASH_BID_PRICE_STRATEGY: scale
- AKASH_BID_PRICE_SCRIPT_PATH: /scripts/price_script.sh

**Startup Sequence**:
1. ✅ Provider service starts
2. ✅ All operators connect (hostname, inventory)
3. ✅ gRPC server listening on 0.0.0.0:8444
4. ✅ Provider attributes fetched successfully
5. ❌ **BIDENGINE-SERVICE FAILS** ← Error occurs here
6. ⚠️  Context canceled, shutdown initiated

## Hypothesis

The bidengine-service is trying to use a client object (likely an inventory or pricing client)
that hasn't been properly initialized. This could be:

1. **Bug in v0.10.7**: Known issue with bidengine-service initialization
2. **Missing provider attributes**: Provider doesn't have required attributes configured on-chain
3. **Timing issue**: Bidengine starts before inventory service is fully ready
4. **Missing configuration**: Required parameter not documented in Helm chart

## Next Steps to Try

### Option 1: Downgrade Provider Version
Try an older, more stable version:
```bash
helm upgrade akash-provider akash/provider \
  --namespace akash-services \
  --set image.tag=0.10.6 \
  --reuse-values
```

### Option 2: Check Provider Attributes
Query the provider's on-chain attributes to ensure they're properly configured:
```bash
# Need to install Akash CLI or use alternative method
provider-services query provider get akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

### Option 3: Minimal Configuration
Try deploying with minimal required configuration to isolate the issue:
```bash
helm upgrade akash-provider akash/provider \
  --namespace akash-services \
  --set bidPriceStrategy=scale \
  --set bidpricecpuscale=0.004 \
  --set bidpricememoryscale=0.0016 \
  --set cpuOvercommitPercent=50 \
  --set memoryOvercommitPercent=50 \
  --reuse-values
```

### Option 4: Enable Debug Logging
Increase logging to get more detailed error information:
```bash
helm upgrade akash-provider akash/provider \
  --namespace akash-services \
  --set log.level=debug \
  --reuse-values
```

## Resources
- Helm Chart: akash/provider (14.0.8)
- Provider Image: ghcr.io/akash-network/provider:0.10.7
- Documentation: https://akash.network/docs
