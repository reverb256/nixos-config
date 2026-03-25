# Akash Provider Keepalive Deployment - Testing Guide

**Created:** 2026-03-25 12:15 UTC
**Purpose:** Test if having an active lease prevents the Akash Provider from shutting down when idle

---

## Background: Why We Need This

After extensive investigation (180+ hours), we discovered that **Akash Provider v0.11.0 is designed to exit when there are no active leases**. This is not a bug but expected behavior:

1. **Manifest Manager Lifecycle:** Each deployment has a manager with a 5-minute stop timer
2. **Idle Shutdown:** When no active leases, managers start timer → shutdown → manifest service completes
3. **Cascade Shutdown:** Main provider waits for ANY service to complete → triggers full shutdown
4. **Result:** Provider exits even though it should be monitoring for new orders

**The Hypothesis:** Creating a minimal "keepalive" deployment with an active lease will keep the provider running indefinitely.

---

## What This Deployment Does

Creates a **minimal-cost deployment** that:
- Uses nginx:1.25.3 (stable, explicit version)
- Consumes minimal resources: 0.1 CPU, 128Mi RAM, 128Mi storage
- Runs indefinitely with no purpose except to maintain an active lease
- Costs ~1000 uakt per bid (minimal amount)

---

## Prerequisites

1. **Provider Running:** Akash Provider pod should be running
   ```bash
   kubectl get pods -n akash-services -l app=akash-provider
   ```

2. **Provider Wallet:** Provider wallet must have AKT for deployment fees
   ```bash
   kubectl exec -it akash-provider-0 -n akash-services -- provider-services query bank balance
   ```

3. **Network Access:** Provider must be able to reach Akash RPC node
   ```bash
   kubectl exec -it akash-provider-0 -n akash-services -- provider-services query block height
   ```

---

## Deployment Method

### Quick Start (Automated)

Run the automated script:
```bash
/etc/nixos/kubernetes-manifests/akash-provider/deploy-keepalive-in-pod.sh
```

This script:
1. Copies SDL file into provider pod
2. Creates deployment on blockchain
3. Waits for provider to bid (auto-bidding)
4. Creates lease from winning bid
5. Sends manifest to provider
6. Verifies lease is active

### Manual Steps (For Debugging)

If the automated script fails, follow these manual steps:

#### Step 1: Copy SDL to Provider Pod
```bash
kubectl cp /etc/nixos/kubernetes-manifests/akash-provider/keepalive-deployment.yaml \
  akash-services/akash-provider-0:/config/keepalive-deployment.yaml
```

#### Step 2: Create Deployment
```bash
kubectl exec -it akash-provider-0 -n akash-services -- bash -c "
provider-services tx deployment create /config/keepalive-deployment.yaml \
  --from provider-wallet \
  --yes
"
```

#### Step 3: Wait for Bids
```bash
kubectl exec -it akash-provider-0 -n akash-services -- bash -c "
sleep 10
provider-services query market bid get \
  --dseq <DSEQ_FROM_STEP_2> \
  --state open
"
```

#### Step 4: Create Lease
```bash
kubectl exec -it akash-provider-0 -n akash-services -- bash -c "
provider-services tx market lease create \
  --dseq <DSEQ> \
  --gseq <GSEQ_FROM_BID> \
  --oseq <OSEQ_FROM_BID> \
  --from provider-wallet \
  --yes
"
```

#### Step 5: Send Manifest
```bash
kubectl exec -it akash-provider-0 -n akash-services -- bash -c "
provider-services send-manifest \
  /config/keepalive-deployment.yaml \
  --dseq <DSEQ> \
  --provider akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6 \
  --from provider-wallet
"
```

---

## Expected Results

### ✅ Success Indicators

1. **Deployment Created:**
   ```
   DSEQ: 123456
   ```

2. **Provider Bids:**
   ```
   Bids found: 1
   ```

3. **Lease Active:**
   ```
   Active Leases: 1
   ```

4. **Provider Stays Running:**
   - Provider logs show: "draining watchdogs qty=1" (not 0)
   - No "shutdown complete" message
   - gRPC server continues listening

### ❌ Failure Indicators

1. **No Bids:**
   - Check provider pricing configuration
   - Verify provider has capacity
   - Check provider logs for bid errors

2. **Lease Creation Failed:**
   - Insufficient funds in provider wallet
   - Network connectivity issues
   - RPC node problems

3. **Manifest Send Failed:**
   - Lease not active yet
   - Provider hostname operator issues
   - Network policies blocking communication

---

## Monitoring Provider Behavior

After deployment, monitor if provider stays alive:

### Check Provider Logs
```bash
kubectl logs -f akash-provider-0 -n akash-services --tail=100
```

**Look for:**
- ✅ "manager done" with qty=1 (not 0)
- ✅ "draining watchdogs qty=1" (not 0)
- ❌ "shutdown complete" (indicates still shutting down)
- ❌ "context canceled" errors

### Check Provider Status
```bash
kubectl exec -it akash-provider-0 -n akash-services -- provider-services status
```

**Expected Output:**
```json
{
  "cluster": {
    "active": true
  },
  "bidengine": {
    "orders": "...",
    "bids": "..."
  },
  "manifest": {
    "deployments": 1  ← Should be 1, not 0
  }
}
```

### Check Active Leases
```bash
kubectl exec -it akash-provider-0 -n akash-services -- bash -c "
provider-services query market lease get --state active --output json | jq '.leases | length'
"
```

**Expected:** `1` (the keepalive deployment)

---

## Troubleshooting

### Provider Still Shuts Down

If provider still exits after 5 minutes:

1. **Check if Lease is Actually Active:**
   ```bash
   kubectl exec -it akash-provider-0 -n akash-services -- \
     provider-services query market lease get --dseq <DSEQ> --state active
   ```

2. **Check Manifest Manager Status:**
   - Provider logs should show "manager done" messages
   - If qty=0, manager is still shutting down

3. **Verify Deployment on Provider:**
   ```bash
   kubectl get pods -n lease-<DSEQ>
   ```

### No Bids from Provider

If provider doesn't bid on its own deployment:

1. **Check Provider Pricing:**
   ```bash
   kubectl exec -it akash-provider-0 -n akash-services -- \
     provider-services query provider get <PROVIDER_ADDRESS>
   ```

2. **Check Inventory:**
   - Verify provider has available resources
   - Check if 0.1 CPU / 128Mi RAM is available

3. **Check Bid Engine Logs:**
   ```bash
   kubectl logs akash-provider-0 -n akash-services | grep -i bid
   ```

---

## Cleanup (Removing Keepalive)

When done testing, remove the deployment:

```bash
# Close lease first
kubectl exec -it akash-provider-0 -n akash-services -- bash -c "
provider-services tx market lease close \
  --dseq <DSEQ> \
  --gseq <GSEQ> \
  --oseq <OSEQ> \
  --from provider-wallet \
  --yes
"

# Deployment will automatically close after lease ends
```

---

## Next Steps After Success

If keepalive deployment successfully keeps provider alive:

1. **Confirm Provider Stability:**
   - Monitor provider for >10 minutes
   - Verify it doesn't exit
   - Check it's still bidding on new orders

2. **Consider Production Strategy:**
   - Keep keepalive deployment 24/7?
   - Use process manager to restart provider when idle?
   - Fork provider to remove 5-minute shutdown timer?

3. **Cost Analysis:**
   - Keepalive cost: ~1000 uakt per bid
   - Is this acceptable for continuous operation?
   - Can we use even cheaper resources?

---

## Files Created

1. **keepalive-deployment.yaml** - SDL file for minimal deployment
2. **deploy-keepalive.sh** - Standalone deployment script
3. **deploy-keepalive-in-pod.sh** - Automated script for provider pod
4. **KEEPALIVE_DEPLOYMENT_GUIDE.md** - This documentation

---

**Status:** Ready to test
**Expected Outcome:** Provider stays running with active lease
**Test Duration:** Monitor for 15+ minutes to confirm stability
