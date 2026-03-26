# Akash Provider Deposit Issue - 2026-03-25

## Problem
Provider keepalive deployment fails with "Deposit invalid" error even with correct deposit format.

## Current Configuration
- **Provider version**: v0.11.0
- **Deposit format**: `--deposit 5akt` (integer AKT denomination)
- **Wallet balance**: 30.22 AKT (sufficient)
- **Chain**: akashnet-2 (mainnet)

## Error Message
```
Error: rpc error: code = Unknown desc = rpc error: code = Unknown desc =
failed to execute message; message index: 0: Deposit invalid
[cosmos/cosmos-sdk@v0.53.5/baseapp/baseapp.go:1052]
with gas used: '35035': unknown request
```

## Attempted Solutions
1. ✅ Changed deposit from `1000000uakt` to `1akt` - FAILED
2. ✅ Changed deposit from `1akt` to `5akt` - FAILED
3. ✅ Verified ConfigMap has correct format - CONFIRMED
4. ✅ Restarted provider multiple times - NO EFFECT

## Root Cause Hypothesis
The error "unknown request" suggests the RPC server is rejecting the transaction format itself, not the deposit amount. This could indicate:
- Version mismatch between CLI and blockchain
- Incorrect transaction construction
- Missing required flags or parameters

## Next Steps
1. Check if `--deposit` flag is actually required
2. Try creating deployment WITHOUT deposit flag
3. Check provider-services CLI documentation for v0.11.0
4. Query blockchain for minimum deposit requirements
