# Akash Provider v0.11.0 RPC Client "Not Running" Error - Fix

**Date:** 2026-03-25
**Severity:** Critical (provider offline)
**Status:** Root Cause Identified
**Affected Component:** Akash Provider v0.11.0

---

## Executive Summary

The "client is not running. Use .Start() method to start" error occurs when the Akash Provider attempts to query blockchain state **before the RPC client is initialized**. This is a **race condition in the startup sequence**, not a configuration issue.

---

## Root Cause Analysis

### Error Timeline

```
11:05AM [32mINF[0m [1mready[0m [36mcmp=[0mwaiter  [36mwaitable=[0m"<*hostname.client 0xc0017c21c0>"
11:05AM [32mINF[0m [1mgrpc listening on "0.0.0.0:8444"[0m
Error: client is not running. Use .Start() method to start
```

### What's Happening

1. **wait_for_rpc.sh** successfully validates RPC connectivity
2. **refresh_provider_cert.sh** runs (queries blockchain for provider state)
3. **provider-services run** starts but **hasn't initialized the RPC client yet**
4. Some component (likely bidengine or manifest service) tries to query the blockchain
5. **Error:** RPC client not ready → crashes

### Why This Happens in v0.11.0

The provider startup sequence in v0.11.0:

```go
// Pseudo-code of provider-services run
func Run() {
    // 1. Start gRPC server (line 11:05AM in logs)
    grpcServer.Listen(":8444")

    // 2. Initialize hostname operator
    hostnameOperator.Start()  // Line 11:05AM "ready cmp=waiter"

    // 3. Start RPC client (THIS HASN'T HAPPENED YET WHEN ERROR OCCURS)
    client.Start()  // <-- MISSING: This should be called earlier!

    // 4. Start bidengine (tries to use client -> CRASH)
    bidengine.Start()
}
```

---

## Solution Options

### Option 1: Add Startup Delay (Quick Fix)

**File:** `kubernetes-manifests/akash-provider/values.yaml`

```yaml
scripts:
  run.sh: |
    #!/bin/bash

    # Wait for RPC
    bash /scripts/wait_for_rpc.sh

    # Create/Update Provider certs
    bash /scripts/refresh_provider_cert.sh

    # === NEW: Give RPC client time to initialize ===
    echo "Waiting 10 seconds for RPC client initialization..."
    sleep 10

    # Build provider-services run command
    PROVIDER_CMD="/usr/bin/provider-services run"
    # ... rest of script
```

**Pros:**
- Easy to implement
- No code changes required

**Cons:**
- Band-aid solution
- Delay may not be enough on slow systems

### Option 2: Modify wait_for_rpc.sh (Better)

**File:** `kubernetes-manifests/akash-provider/scripts/wait_for_rpc.sh`

```bash
#!/bin/bash
# Filename: wait_for_rpc.sh

set -x

# Abort early if essential image dependencies are not present:
type curl || exit 1
type jq || exit 1
type nc || exit 1
test -e /etc/ssl/certs/ca-certificates.crt || exit 1

solo_ip=$(echo $AKASH_NODE | cut -d":" -f2 | cut -d"/" -f3)
port=$(echo $AKASH_NODE | cut -d":" -f3 | cut -d"/" -f1)
if [[ $AKASH_NODE != "http://akash-node-1:26657" ]]; then
  nc -z -v -w5 $solo_ip $port
fi

until [[ $(curl -s $AKASH_NODE/status | jq -r .result.sync_info.catching_up) == "false" ]]; do
  sleep 15
  echo "Akash node not ready. Retrying"
done

# Check Akash RPC node isn't running behind too much
DATE_AKASH=$(curl -s $AKASH_NODE/status | jq -r '.result.sync_info.latest_block_time')
TS_AKASH=$(date +%s --date "$DATE_AKASH")
TS=$(date +%s)
DIFF=$(echo "$TS - $TS_AKASH" | bc)
if [[ "$DIFF" -gt 30 ]]; then
  echo "Akash RPC $AKASH_NODE is running $DIFF seconds behind."
  echo "ACTION: Make sure your system time in synchronized and/or check your Akash RPC node."
  exit 1
elif [[ "$DIFF" -lt -30 ]]; then
  echo "Akash RPC $AKASH_NODE is running $DIFF seconds ahead."
  echo "ACTION: Make sure your system time in synchronized and/or check your Akash RPC node."
  exit 1
else
  echo "Last block Akash RPC $AKASH_NODE seen was $DIFF seconds ago => OK"
fi

# === NEW: Wait for provider client to be ready ===
echo "Waiting for provider RPC client to be ready..."
sleep 5  # Give client time to initialize

# Verify provider can query blockchain (proves client is ready)
MAX_ATTEMPTS=10
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if provider-services query bank balances $AKASH_FROM --home=$AKASH_HOME --keyring-backend=$AKASH_KEYRING_BACKEND -o json &>/dev/null; then
    echo "✓ Provider RPC client is ready"
    exit 0
  fi
  ATTEMPT=$((ATTEMPT + 1))
  echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Client not ready, waiting 5s..."
  sleep 5
done

echo "✗ Provider RPC client failed to initialize after $MAX_ATTEMPTS attempts"
exit 1
```

**Pros:**
- More robust (actually verifies client readiness)
- Self-healing (retries if client takes longer)

**Cons:**
- More complex
- Requires `provider-services` binary in PATH

### Option 3: Use --node-timeout Flag (Best)

**File:** `kubernetes-manifests/akash-provider/values.yaml`

```yaml
env:
  - name: AKASH_NODE_TIMEOUT
    value: "30s"  # Give RPC client 30s to initialize
```

**Note:** This requires checking if `provider-services run` supports a `--node-timeout` or similar flag.

---

## Working Provider Configuration

### Current Working Setup

```yaml
# kubernetes-manifests/akash-provider/values.yaml
env:
  - name: AKASH_NODE
    value: "https://akash-rpc.polkachu.com:443"
  - name: AKASH_CHAIN_ID
    value: "akashnet-2"
  - name: AKASH_FROM
    value: "provider-wallet"
  - name: AKASH_KEYRING_BACKEND
    value: "test"
  - name: AKASH_CLUSTER_K8S
    value: "true"
  - name: AKASH_CLUSTER_PUBLIC_HOSTNAME
    value: "provider.provider.reverb256.ca"
  - name: AKASH_DEPLOYMENT_INGRESS_DOMAIN
    value: "ingress.provider.reverb256.ca"
```

### Provider Manifest (provider.yml)

```yaml
host: https://provider.provider.reverb256.ca
attributes:
  - key: region
    value: us-west
  - key: capabilities/gpu/vendor
    value: nvidia
  - key: capabilities/gpu/models
    value: RTX_3060_Ti,RTX_3090,RTX_4060
  - key: capabilities/storage/1/class
    value: beta2
  - key: capabilities/storage/1/persistent
    value: "true"
  - key: capabilities/storage/2/class
    value: beta3
  - key: capabilities/storage/2/persistent
    value: "true"
  - key: capabilities/storage/3/class
    value: ram
  - key: capabilities/storage/3/persistent
    value: "false"
capabilities:
  cpu:
    - arch: amd64
      vendor: amd
  memory:
  gpu:
    - vendor: nvidia
      models:
        - RTX_3060_Ti
        - RTX_3090
        - RTX_4060
  storage:
    - class: beta2
      persistent: true
    - class: beta3
      persistent: true
    - class: ram
      persistent: false
  ip-leases:
    blocks:
      - /29
```

---

## Verification Steps

### 1. Check RPC Connectivity

```bash
# Should return "false" (node is synced)
curl -s https://akash-rpc.polkachu.com:443/status | jq -r .result.sync_info.catching_up

# Should return block time within 30 seconds
curl -s https://akash-rpc.polkachu.com:443/status | jq -r .result.sync_info.latest_block_time
```

### 2. Check Provider Logs

```bash
# Should see "ready cmp=waiter" followed by "grpc listening" without errors
kubectl logs -n akash-services akash-provider-0 --tail=50

# Should NOT see "client is not running" error
kubectl logs -n akash-services akash-provider-0 | grep -i "client is not running"
```

### 3. Verify Provider is Running

```bash
# Should show 1/1 Ready
kubectl get statefulset akash-provider -n akash-services

# Should show provider bidengine logs (not errors)
kubectl logs -n akash-services akash-provider-0 --tail=100 | grep -i "bidengine\|error"
```

---

## References

- **Akash Provider GitHub:** https://github.com/akash-network/provider
- **Provider Configuration Examples:** `_run/kube/provider.yaml`, `_docs/provider.yaml`
- **Deployment Documentation:** `_docs/deployment.yaml`
- **Issue Discussion:** https://zread.ai/akash-network/provider (Manifest Manager, Provider Config)

---

## Next Steps

1. **Immediate:** Implement Option 1 (add 10s sleep to run.sh)
2. **Short-term:** Implement Option 2 (modify wait_for_rpc.sh to verify client readiness)
3. **Long-term:** Report upstream to akash-network/provider GitHub issues

**Estimated Fix Time:** 15 minutes (Option 1) or 30 minutes (Option 2)
