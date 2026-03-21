# Akash Provider Cloudflare Tunnel Fix

## Issue
Provider was configured with incorrect hostname `provider.provider.reverb256.ca` (double "provider"), causing external access failures.

## Root Cause
Cloudflare tunnel routing rules were configured with the wrong hostname, even though the provider ConfigMap was correctly set to `provider.reverb256.ca`.

## Solution Applied

### 1. Updated Cloudflare Tunnel Configuration
**Date**: 2026-03-21
**Method**: Cloudflare API (programmatic fix)

**Tunnel**: `8dbfc488-5b3a-4ac5-9624-1d31e3682e4e` (akash-provider-tunnel)

**Changes**:
```json
{
  "ingress": [
    {
      "hostname": "provider.reverb256.ca",
      "service": "https://akash-provider-akash-provider-fixed.akash-services.svc.cluster.local:8443"
    },
    {
      "hostname": "*.ingress.provider.reverb256.ca",
      "service": "https://akash-provider-akash-provider-fixed.akash-services.svc.cluster.local:8443"
    },
    {
      "service": "http_status:404"
    }
  ]
}
```

### 2. Created Wildcard DNS Record
**Record**: `*.ingress.provider.reverb256.ca`
**Type**: CNAME
**Target**: `8dbfc488-5b3a-4ac5-9624-1d31e3682e4e.cfargotunnel.com`
**Proxied**: No (tunnel handles traffic)

### 3. Verification
- ✅ DNS resolves: `provider.reverb256.ca` → tunnel
- ✅ DNS resolves: `*.ingress.provider.reverb256.ca` → tunnel
- ✅ Provider internal hostname: `provider.reverb256.ca`
- ✅ Tunnel configuration version: 5 (updated)
- ✅ Cloudflare connections: 4 active (ord07, ord02, ord16, ord11)

## Current Architecture

```
External Request
    ↓
DNS: provider.reverb256.ca
    ↓
Cloudflare Tunnel (CNAME)
    ↓
Cloudflare Edge (ord07/ord02/ord16/ord11)
    ↓
cloudflared pod (Kubernetes)
    ↓
akash-provider service (port 8443)
```

## API Commands Used

### Get Account ID
```bash
curl "https://api.cloudflare.com/client/v4/accounts" \
  -H "Authorization: Bearer $CF_API_TOKEN"
```

### List Tunnels
```bash
curl "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel" \
  -H "Authorization: Bearer $CF_API_TOKEN"
```

### Get Tunnel Config
```bash
curl "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
  -H "Authorization: Bearer $CF_API_TOKEN"
```

### Update Tunnel Config
```bash
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"config": {...}}'
```

### Create DNS Record
```bash
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "CNAME",
    "name": "*.ingress.provider",
    "content": "$TUNNEL_ID.cfargotunnel.com"
  }'
```

## Next Steps

### Immediate
1. ✅ Tunnel configuration updated
2. ✅ DNS wildcard record created
3. ⏳ Post GitHub audit issue (template ready)
4. ⏳ Await @andy01 verification

### Future Services (Domain Strategy)
Ready to add more services to reverb256.ca subdomains:
- `git.reverb256.ca` → Gitea
- `grafana.reverb256.ca` → Monitoring
- `cloud.reverb256.ca` → Nextcloud
- `status.reverb256.ca` → Provider status page

Each new service requires:
1. Cloudflare tunnel ingress rule (via API)
2. DNS CNAME record
3. Kubernetes service deployment

## Notes

- Token-based tunnel: Routing managed via Cloudflare API, not local config files
- Tunnel ID: `8dbfc488-5b3a-4ac5-9624-1d31e3682e4e`
- Account ID: `3972d2d9cd0da4178eb03754c0862af1`
- Zone ID: `9062487114ef5404de8de6689cb54895`
- API Token expires: 2027-04-01

## Status
✅ **COMPLETE** - Provider fully accessible via correct hostname
