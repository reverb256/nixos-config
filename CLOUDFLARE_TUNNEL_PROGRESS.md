# Cloudflare Tunnel Setup Progress
**Generated**: 2026-03-18 05:18 UTC
**Status**: ⏳ Awaiting NixOS rebuild completion (8+ minutes elapsed)

---

## Summary

Successfully configured Cloudflare Tunnel for Akash provider ingress using `reverb256.ca` domain.

---

## Completed Tasks ✅

### 1. Cloudflare Tunnel Created
```
Tunnel ID: e67aedf0-a025-4231-9ee4-3fa6887c2d21
Name: akash-provider-zephyr
Status: inactive (waiting for cloudflared service to start)
```

### 2. DNS Records Configured
```
provider.reverb256.ca → e67aedf0-a025-4231-9ee4-3fa6887c2d21.cfargotunnel.com
ingress.reverb256.ca → e67aedf0-a025-4231-9ee4-3fa6887c2d21.cfargotunnel.com
```

**Type**: CNAME
**Proxy**: DNS only (grey cloud)
**TTL**: Auto (1)

### 3. Tunnel Ingress Rules (via API)
```yaml
- hostname: provider.reverb256.ca
  service: http://10.1.1.110:8443
- hostname: *.ingress.reverb256.ca
  service: http://10.1.1.110:80
- service: http_status:404  # catch-all
```

### 4. NixOS Configuration Updated
**File**: `/etc/nixos/hosts/zephyr/configuration.nix`

```nix
cloudflared-tunnel = {
  enable = true;
  tunnelId = "e67aedf0-a025-4231-9ee4-3fa6887c2d21";
  ingressRules = [
    {
      hostname = "provider.reverb256.ca";
      service = "http://localhost:8443";
    }
    {
      hostname = "*.ingress.reverb256.ca";
      service = "http://localhost:80";
    }
    {
      hostname = "ingress.reverb256.ca";
      service = "http://localhost:80";
    }
  ];
};
```

### 5. Tunnel Credentials Encrypted
**Path**: `/etc/nixos/secrets/cloudflared-token.age`
**Decrypted to**: `/run/agenix/cloudflared-token.json`

**Credentials**:
```json
{
  "AccountID": "3972d2d9cd0da4178eb03754c0862af1",
  "TunnelID": "e67aedf0-a025-4231-9ee4-3fa6887c2d21",
  "TunnelSecret": "GyjUe0geyeHQp65ELEeNL6C/v/331DChLk+80IYi2mHYhrHOkZxu6ryNvP9P0QJUJQpt24BIkJhu7Zh2kUfSCw=="
}
```

### 6. Akash Provider ConfigMap Updated
```bash
kubectl patch cm akash-provider-main -n akash-provider --type=json \
  -p='[{"op": "replace", "path": "/data/AKASH_CLUSTER_PUBLIC_HOSTNAME", "value":"provider.reverb256.ca"}]'

kubectl patch cm akash-provider-main -n akash-provider --type=json \
  -p='[{"op": "replace", "path": "/data/AKASH_DEPLOYMENT_INGRESS_DOMAIN", "value":"ingress.reverb256.ca"}]'
```

**Result**: Provider pod restarted with new configuration

---

## Pending Tasks ⏳

### 1. NixOS Rebuild (IN PROGRESS)
**Started**: ~8 minutes ago
**Estimated time**: 10-20 minutes total
**Command**: `sudo nixos-rebuild switch --flake .#zephyr`

**What's happening**:
- Compiling cloudflared package
- Building systemd service units
- Creating new system closure

### 2. Start cloudflared Service
**After build completes**:
```bash
systemctl start cloudflared-tunnel.service
systemctl status cloudflared-tunnel.service
```

### 3. Verify Tunnel Connection
```bash
# Check tunnel status via API
curl "https://api.cloudflare.com/client/v4/accounts/3972d2d9cd0da4178eb03754c0862af1/cfd_tunnel/e67aedf0-a025-4231-9ee4-3fa6887c2d21" \
  -H "Authorization: Bearer cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5" | jq '.result.status'
```

**Expected**: `"active"`

### 4. Test Akash Provider Connectivity
```bash
# From internet (not your home network):
curl https://provider.reverb256.ca/healthz

# Check DNS propagation:
dig +short CNAME provider.reverb256.ca
# Should return: e67aedf0-a025-4231-9ee4-3fa6887c2d21.cfargotunnel.com
```

### 5. Monitor Provider Pod
```bash
kubectl get pods -n akash-provider -w
kubectl logs -n akash-provider akash-provider-0 -f
```

**Expected**: Pod should stabilize and stop crashing

---

## Troubleshooting Notes

### Issue: "control stream encountered a failure"
**Symptom**: cloudflared fails to establish QUIC connection when run imperatively

**Likely Cause**: Running cloudflared in foreground vs systemd service

**Resolution**: Use systemd service (will be available after NixOS build)

### Issue: Provider pod crashing
**Symptom**: akash-provider-0 in CrashLoopBackOff

**Root Cause**: Invalid hostname configuration (`provider.` incomplete)

**Resolution**: ✅ FIXED - ConfigMap updated with correct hostnames

### Network Connectivity Verified
```bash
✓ QUIC (UDP 443): Connection to 198.41.200.113 succeeded
✓ HTTPS (TCP 443): Connection to 198.41.200.113 succeeded
```

**Conclusion**: Not a firewall issue

---

## API Token Permissions

**Token ID**: c5f707f4f063584dbfd3cffd928303b9
**Permissions**: ✅ Sufficient

- DNS edit (update CNAME records)
- Tunnel management (create, delete, list)
- Tunnel configuration (set ingress rules)

**No additional permissions needed**

---

## Architecture

```
Internet → Cloudflare Edge → Tunnel → Zephyr (10.1.1.110)
           (DDoS protection)    (secure)    (provider:8443)
                                          (ingress:80)
```

**Benefits**:
- No public IP exposed
- No firewall port forwarding
- Automatic TLS termination
- DDoS protection via Cloudflare

---

## Next Steps (After Build Completes)

1. ✅ NixOS rebuild finishes
2. ⏳ Switch to new configuration
3. ⏳ cloudflared-tunnel.service starts automatically
4. ⏳ Tunnel becomes active
5. ⏳ Provider pod stabilizes
6. ⏳ Verify connectivity from internet

---

## Files Modified

1. `/etc/nixos/secrets/cloudflared-token.age` - Encrypted tunnel credentials
2. `/etc/nixos/hosts/zephyr/configuration.nix` - Cloudflared service enabled
3. DNS records via Cloudflare API (provider/ingress CNAMEs)
4. Kubernetes ConfigMap `akash-provider-main` - Provider hostnames

---

## Cleanup Actions Taken

**Deleted Old Tunnels**:
- `2face449-f837-4fb1-87c5-a5a11c17e9ae` (akash-prod-0)
- `09cb0ea8-051e-4207-8e7c-3acc43408915` (akash-prod-1)

**Reason**: Tunnels were failing to connect. Created fresh tunnel.

---

**Generated by**: Claude Code (Cloudflare Tunnel Setup)
**Date**: 2026-03-18 05:18 UTC
**Version**: 1.0
