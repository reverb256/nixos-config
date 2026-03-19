# Akash Provider Diagnostic - 2026-03-19 22:30

## Current Status
- **Provider Pod**: CrashLoopBackOff (Exit Code: 1)
- **Error**: `Error: client is not running. Use .Start() method to start` from bidengine-service
- **Pricing Strategy**: scale (tried shellScript with same result)

## What's Working
✅ Certificate valid on-chain (serial: 189E1B2C59B6BFF3)
✅ Wallet imported successfully
✅ Init container completes successfully
✅ Provider registration successful
✅ gRPC server starts listening on port 8444
✅ Hostname operator connection successful
✅ Inventory operator connection successful
✅ Provider attributes fetched successfully

## Error Sequence
```
[3:29AM] INF starting provider service
[3:29AM] INF all waitables ready
[3:29AM] INF starting with existing reservations (module=provider-cluster, qty=0)
[3:29AM] INF fetched provider attributes (module=bidengine-service, provider=akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6)
Error: client is not running. Use .Start() method to start
[3:29AM] INF grpc listening on "0.0.0.0:8444"
[3:29AM] DBG received shutdown request (error="context canceled" module=bidengine-service)
```

## Configuration Details

### Helm Values
- **Bid Pricing Strategy**: scale
- **CPU Overcommit**: 0%
- **Memory Overcommit**: 0%
- **Max Deployments**: 100
- **Withdrawal Period**: 720 blocks
- **Certificate Issuer**: disabled

### Environment Variables
- **AKASH_FROM**: provider-wallet
- **AP_CERT_ISSUER_ENABLED**: false
- **AKASH_BID_PRICE_SCRIPT_PATH**: /scripts/price_script.sh

### CRDs Installed
- manifests.akash.network
- providerhosts.akash.network
- providerleasedips.akash.network

### Resources Created
- No manifests found
- No provider hosts found
- No leased IPs found

## Root Cause Hypothesis

The bidengine-service is failing during initialization because it's trying to use a client
that hasn't been started. This could be due to:

1. **Missing provider attributes**: The provider might not have the required attributes configured
2. **Inventory service timing**: The bid engine might be starting before the inventory service is fully ready
3. **Missing configuration**: There might be a required configuration parameter that's not set

## Next Steps

1. Check if provider attributes are properly configured on-chain
2. Verify inventory operator has discovered hardware resources
3. Check for missing environment variables or configuration parameters
4. Review Akash provider documentation for bidengine-service requirements
