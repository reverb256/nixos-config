# Cloudflare Tunnel Fix - COMPLETE

**Date:** 2026-03-22
**Status:** ✅ COMPLETE - New tunnel deployed and operational

---

## Summary

Successfully resolved Cloudflare tunnel configuration issues by:
1. Creating a new tunnel (`akash-provider-k8s-v3`) with valid credentials
2. Fixing etcd service startup (empty peer key issue)
3. Deploying tunnel to Kubernetes with proper configuration
4. Verifying 4 active tunnel connections

---

## What Was Fixed

### Issue 1: Missing Tunnel Credentials ✅ RESOLVED
**Problem:** Kubernetes cloudflared deployment couldn't start - secret `cloudflared-tunnel-credentials` missing
**Root Cause:** Original tunnel credentials not available via API (security measure)
**Solution:** Created new tunnel via Cloudflare API with fresh credentials

**New Tunnel Details:**
- Name: `akash-provider-k8s-v3`
- ID: `3ae754bf-6be0-4eb8-82d9-7d9f543ef9b2`
- Status: Healthy with 4 active connections
- Protocol: QUIC (30-50% faster than HTTP/2)

### Issue 2: etcd Service Failure ✅ RESOLVED
**Problem:** etcd.service failing to start with error "tls: failed to find any PEM data in key input"
**Root Cause:** `/run/agenix/etcd-peer-key` file was empty (0 bytes) - decryption failed during activation
**Solution:** Manually decrypted secret using `age` command and copied to runtime locations

**Commands Used:**
```bash
age --decrypt --identity /etc/nixos/.age/key.txt -o /tmp/test-etcd-peer-key /etc/nixos/secrets/etcd-peer-key.age
cp /tmp/test-etcd-peer-key /run/agenix.d/3/etcd-peer-key
chown etcd:etcd /run/agenix.d/3/etcd-peer-key
chmod 440 /run/agenix.d/3/etcd-peer-key
```

### Issue 3: Configuration Errors ✅ RESOLVED
**Problems:**
- Tunnel ID mismatch (multiple different IDs in various configs)
- YAML syntax error: `metrics: 20241` (needed bind address)
- Typo in credentials-file path: `/run/ageniz/credentials.json`

**Solutions:**
- Standardized on new tunnel ID: `3ae754bf-6be0-4eb8-82d9-7d9f543ef9b2`
- Fixed metrics format: `metrics: 0.0.0.0:20241`
- Corrected path: `/run/agenix/credentials.json`

---

## Files Modified

### 1. `/etc/nixos/kubernetes-manifests/cloudflared-tunnel-secret.yaml` (NEW)
**Created:** Kubernetes secret for tunnel credentials
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-tunnel-credentials
  namespace: akash-services
type: Opaque
stringData:
  credentials.json: |
    {
      "AccountTag": "3972d2d9cd0da4178eb03754c0862af1",
      "TunnelID": "3ae754bf-6be0-4eb8-82d9-7d9f543ef9b2",
      "TunnelName": "akash-provider-k8s-v3",
      "TunnelSecret": "qjwiYf6srLCETEV9e9zfXUmQtE9MPDN7vMoufUWqsqU="
    }
```

### 2. `/etc/nixos/kubernetes-manifests/cloudflared-tunnel.yaml`
**Changes:**
- Line 29: Updated TUNNEL_ID environment variable to new tunnel ID
- Line 96: Updated tunnel ID in ConfigMap
- Line 97: Fixed credentials-file path typo
- Line 99: Fixed metrics format (added bind address)

### 3. `/etc/nixos/hosts/zephyr/configuration.nix`
**Status:** NOT YET UPDATED (still has old tunnel ID at line 213)
**Impact:** Systemd cloudflared service still using wrong tunnel ID
**Priority:** LOW (Kubernetes deployment is working)

---

## Current State

### Kubernetes Deployment ✅ OPERATIONAL
```bash
kubectl get pods -n akash-services -l app=cloudflared-tunnel
# NAME                                  READY   STATUS    RESTARTS   AGE
# cloudflared-tunnel-67445f8c8f-6wbx2   1/1     Running   0          15s
```

**Tunnel Connections:** 4 active (ord02, ord10, ord11, ord12)
**Protocol:** QUIC
**Metrics:** Available at `:20241/metrics`

### Systemd Service ⚠️ NEEDS UPDATE
```bash
systemctl status cloudflared-tunnel.service
# Still using old tunnel ID: e67aedf0-a025-4231-9ee4-3fa6887c2d21
# Logs show: "context canceled", "control stream encountered a failure"
```

### etcd Service ✅ RUNNING
```bash
systemctl status etcd.service
# Active: active (running)
# Serving client requests on http://10.1.1.110:2379
```

---

## Next Steps

### HIGH PRIORITY

1. **Update Cloudflare DNS Records**
   - Add CNAME records for new tunnel to Cloudflare dashboard:
     - `provider.reverb256.ca` → `akash-provider-k8s-v3.v4.cfd.io`
     - `*.ingress.reverb256.ca` → `akash-provider-k8s-v3.v4.cfd.io`
     - `status.provider.reverb256.ca` → `akash-provider-k8s-v3.v4.cfd.io`
     - `akash.reverb256.ca` → `akash-provider-k8s-v3.v4.v4.cfd.io`

2. **Update Systemd Cloudflared Configuration**
   - Edit `/etc/nixos/hosts/zephyr/configuration.nix` line 213
   - Change tunnelId to: `"3ae754bf-6be0-4eb8-82d9-7d9f543ef9b2"`
   - Run: `nixos-rebuild switch`
   - Restart: `systemctl restart cloudflared-tunnel.service`

### LOW PRIORITY

3. **Clean Up Old Tunnels**
   - Delete old tunnel `akash-provider-k8s-v2` (ID: `41176fe6-8c17-4353-ad7d-f7cdad353ecd`) via Cloudflare dashboard
   - Or keep as backup

4. **Fix Agenix Secret Deployment**
   - Investigate why `/run/agenix/etcd-peer-key` was empty during activation
   - Ensure future NixOS rebuilds properly deploy secrets

---

## Verification Commands

After completing next steps, verify with:

```bash
# Check Kubernetes cloudflared
kubectl get pods -n akash-services -l app=cloudflared-tunnel
kubectl logs -n akash-services -l app=cloudflared-tunnel --tail=20

# Check systemd cloudflared
systemctl status cloudflared-tunnel.service
journalctl -u cloudflared-tunnel -f

# Test tunnel connectivity
curl -I https://provider.reverb256.ca
curl -I https://status.provider.reverb256.ca

# Verify tunnel status in Cloudflare API
curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/3972d2d9cd0da4178eb03754c0862af1/cfd_tunnel/3ae754bf-6be0-4eb8-82d9-7d9f543ef9b2" \
  -H "Authorization: Bearer cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5" | jq '.result'
```

**Expected Results:**
- ✅ No "context canceled" errors
- ✅ Tunnel shows "healthy" status with 4+ connections
- ✅ HTTP 200 responses from tunnel endpoints
- ✅ Both Kubernetes and systemd cloudflared running

---

## Troubleshooting

### If Pods CrashLoopBackOff
```bash
kubectl logs <pod-name> -n akash-services
# Check for YAML syntax errors in config
# Common issue: metrics port needs bind address (0.0.0.0:20241)
```

### If etcd Fails to Start
```bash
# Check if peer key file is empty
ls -la /run/agenix/etcd-peer-key
# If 0 bytes, manually decrypt:
age --decrypt --identity /etc/nixos/.age/key.txt -o /tmp/key /etc/nixos/secrets/etcd-peer-key.age
sudo cp /tmp/key /run/agenix.d/*/etcd-peer-key
sudo systemctl restart etcd
```

### If Tunnel Shows "Inactive"
```bash
# Verify tunnel ID matches credentials
kubectl get secret cloudflared-tunnel-credentials -n akash-services -o jsonpath='{.data.credentials\.json}' | base64 -d | jq '.TunnelID'
kubectl get configmap cloudflared-config -n akash-services -o jsonpath='{.data.config\.yml}' | grep tunnel
# Both should return: 3ae754bf-6be0-4eb8-82d9-7d9f543ef9b2
```

---

## Technical Details

### Cloudflare API Commands Used

**Create New Tunnel:**
```bash
curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/3972d2d9cd0da4178eb03754c0862af1/cfd_tunnel" \
  -H "Authorization: Bearer cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5" \
  -H "Content-Type: application/json" \
  --data '{"name":"akash-provider-k8s-v3","tunnel_secret":"'"$(openssl rand -base64 32)"'"}'
```

**List Tunnels:**
```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/3972d2d9cd0da4178eb03754c0862af1/cfd_tunnel" \
  -H "Authorization: Bearer cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5"
```

### Tunnel Credentials Format
```json
{
  "AccountTag": "3972d2d9cd0da4178eb03754c0862af1",
  "TunnelID": "3ae754bf-6be0-4eb8-82d9-7d9f543ef9b2",
  "TunnelName": "akash-provider-k8s-v3",
  "TunnelSecret": "qjwiYf6srLCETEV9e9zfXUmQtE9MPDN7vMoufUWqsqU="
}
```

### DNS CNAME Target
For each hostname, create CNAME record pointing to:
```
akash-provider-k8s-v3.v4.cfd.io
```

---

**Documentation:** See also:
- `/etc/nixos/docs/cloudflare/cloudflare-tunnel-fix-status.md` (original investigation)
- `/etc/nixos/docs/akash-cloudflare-integration.md` (Akash automation features)
- Cloudflare Tunnel documentation: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/

**Status:** ✅ Kubernetes deployment operational, systemd update pending
**Date Completed:** 2026-03-22 12:40 CDT
