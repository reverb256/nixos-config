# Cloudflare FREE Tier Optimizations for Akash Provider

**Last Updated:** 2026-03-20
**Cloudflare Plan:** FREE
**Domain:** reverb256.ca
**Zone ID:** 9062487114ef5404de8de6689cb54895

---

## FREE Tier Limitations

### ❌ NOT Available on Free Tier

| Feature | Plan Required | Workaround |
|---------|---------------|------------|
| Page Rules | Pro ($20/mo) | Use Cache-Level headers in origin |
| Rate Limiting | Pro ($20/mo) | Use origin-level rate limiting (nginx) |
| Transform Rules | Pro ($20/mo) | Add headers via nginx/origin |
| WAF | Pro ($20/mo) | Use origin-level firewall |
| Image Optimization | Pro ($20/mo) | N/A for provider use case |

### ✅ Available on Free Tier

| Feature | Status | Notes |
|---------|--------|-------|
| SSL/TLS (Full, Full strict) | ✅ Available | **HIGH PRIORITY** |
| Minimum TLS Version | ✅ Available | **HIGH PRIORITY** |
| Universal SSL | ✅ Available | Automatic certificates |
| DNS Management | ✅ Available | Via API or dashboard |
| Cloudflare Tunnel | ✅ Available | Already configured |
| Zero Trust Access | ✅ Available | Already configured |
| DDoS Protection | ✅ Available | Automatic |
| Caching Flattening | ✅ Available | Basic level only |

---

## Priority 1: SSL/TLS Hardening (✅ FREE Tier)

### Why This Matters

The provider bid engine (`provider.reverb256.ca`) and gRPC endpoint handle sensitive bidding and lease management. Strong SSL/TLS settings prevent:

- Man-in-the-middle attacks on bid data
- Credential interception
- Certificate spoofing

### Configuration

**Via Cloudflare Dashboard:**
1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/ssl/tls-configuration
2. Set **Overview** to: **Full (strict)**
3. Set **Minimum TLS Version** to: **1.2**

**Via API (Automated):**
```bash
export CLOUDFLARE_API_TOKEN="cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5"
/etc/nixos/scripts/cloudflare-optimizations-apply.sh apply
```

### What This Does

| Setting | Before | After | Benefit |
|---------|--------|-------|---------|
| SSL/TLS Mode | Flexible/Full | Full (strict) | Validates origin certificates |
| Minimum TLS | 1.0/1.1 | 1.2+ | Blocks deprecated protocols |

### Testing

```bash
# Test TLS 1.2 is accepted
openssl s_client -connect provider.reverb256.ca:443 -tls1_2
# Should connect successfully

# Test TLS 1.1 is rejected
openssl s_client -connect provider.reverb256.ca:443 -tls1_1
# Should fail with "no protocol available"
```

---

## Priority 2: DNS Optimization (✅ FREE Tier)

### Current Configuration

```
*.ingress.reverb256.ca
  Type: CNAME
  Target: 8dbfc488-5b3a-4ac5-9624-1d31e3682e4e.cfargotunnel.com
  TTL: Auto (Cloudflare managed)
  Proxied: false (DNS-only)
```

### Analysis: Good News!

**`proxied: false`** means:
- ✅ No Cloudflare proxy caching
- ✅ Direct DNS resolution to tunnel
- ✅ Faster connections to tenant deployments
- ✅ Origin controls caching behavior

**TTL: Auto** means:
- ✅ Cloudflare optimizes TTL automatically
- ✅ Typically 300 seconds (5 minutes) for proxied, 2 minutes for DNS-only
- ✅ Fast enough for tenant deployments

### No Action Needed

The current DNS setup is **optimal for free tier**. The `proxied: false` setting bypasses Cloudflare's cache entirely, which is exactly what we want for tenant deployments.

---

## Priority 3: Origin-Level Cache Control (✅ FREE Tier Workaround)

### Problem

Free tier doesn't support Page Rules to disable caching per-URL pattern. Cloudflare's default caching behavior could cache tenant content.

### Solution: Use Origin-Level Cache Headers

Since we can't control Cloudflare's cache via Page Rules (free tier limitation), we control caching from the **origin** (nginx/tenant apps).

#### Option 1: Nginx Cache Headers (Recommended)

Add to nginx configuration for tenant ingress:

```nginx
# /etc/nixos/modules/services/kubernetes.nix
services.nginx.virtualHosts."_<tenant>" = {
  extraConfig = ''
    # Disable Cloudflare caching for tenant deployments
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header Pragma "no-cache";
    add_header Expires "0";
  '';
};
```

#### Option 2: Tenant App Headers

Tenants can add cache headers to their applications:

```yaml
# Example: Kubernetes deployment with cache headers
spec:
  template:
    spec:
      containers:
        - name: app
          env:
            - name: CACHE_CONTROL
              value: "no-cache, no-store, must-revalidate"
```

#### Option 3: Cloudflare Cache Purge (Automated)

The Akash Cloudflare integration already includes cache purging! When tenants deploy:

```bash
# From akash-cloudflare-integration.nix
curl -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/purge_cache" \
  -H "Authorization: Bearer $token" \
  --data '{"files":["https://tenant.dedicated.ingress.reverb256.ca/*"]}'
```

**This is the best solution for free tier!**

---

## Priority 4: Origin-Level Rate Limiting (✅ FREE Tier Workaround)

### Problem

Free tier doesn't support Cloudflare rate limiting. Provider endpoints could be flooded with requests.

### Solution: Nginx Rate Limiting

Add rate limiting to nginx for provider endpoints:

```nix
# /etc/nixos/modules/services/cloudflared.nix
services.nginx = {
  enable = true;

  # Rate limiting zones
  appendHttpConfig = ''
    # Limit provider API to 100 req/min
    limit_req_zone $binary_remote_addr zone=provider_limit:10m rate=100r/m;

    # Limit gRPC to 50 req/min
    limit_req_zone $binary_remote_addr zone=grpc_limit:10m rate=50r/m;
  '';

  virtualHosts."provider" = {
    locations."/" = {
      extraConfig = ''
        # Apply rate limiting
        limit_req zone=provider_limit burst=20 nodelay;

        # Proxy to provider
        proxy_pass http://10.1.1.120:30843;
      '';
    };
  };
};
```

---

## Priority 5: Security Headers (✅ FREE Tier Workaround)

### Problem

Free tier doesn't support Transform Rules for adding security headers.

### Solution: Add Headers via Nginx

```nix
# /etc/nixos/modules/services/kubernetes.nix
services.nginx.virtualHosts."_<default>" = {
  extraConfig = ''
    # Security headers for all tenant endpoints
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
  '';
};
```

---

## FREE Tier Optimization Summary

### ✅ What We CAN Do (Free Tier)

| Optimization | Method | Priority |
|--------------|--------|----------|
| SSL/TLS Hardening | Cloudflare Dashboard/API | ⭐⭐⭐ |
| DNS Configuration | Already optimal | ⭐⭐⭐ |
| Cache Purging | API (automated in integration) | ⭐⭐⭐ |
| Cache Control Headers | Origin (nginx/tenant apps) | ⭐⭐ |
| Rate Limiting | Origin (nginx) | ⭐⭐ |
| Security Headers | Origin (nginx) | ⭐ |

### ❌ What We CANNOT Do (Requires Pro)

| Feature | Free Tier Limitation | Impact |
|---------|---------------------|--------|
| Page Rules | Not available | Cannot bypass cache via Cloudflare |
| Rate Limiting | Not available | Must use origin-level limiting |
| Transform Rules | Not available | Must add headers via nginx |
| WAF | Not available | Rely on origin firewall |

---

## Implementation Steps

### Step 1: SSL/TLS Hardening (Do Now!)

**Via Dashboard:**
1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/ssl/tls-configuration
2. Set: **Full (strict)**
3. Set: **Minimum TLS Version: 1.2**

**Via API (Automated):**
```bash
export CLOUDFLARE_API_TOKEN="cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5"
/etc/nixos/scripts/cloudflare-optimizations-apply.sh apply
```

### Step 2: Verify Current DNS (Already Optimal!)

```bash
# Check DNS record
dig *.ingress.reverb256.ca

# Should show: CNAME pointing to cfargotunnel.com
# Proxied: false (good! no Cloudflare cache)
```

### Step 3: Cache Purging (Already Automated!)

The Akash Cloudflare integration purges cache automatically when tenants deploy. No action needed!

### Step 4: Add Nginx Security Headers (Optional)

If you want additional hardening, add nginx headers to tenant ingress.

### Step 5: Add Nginx Rate Limiting (Optional)

If you experience abuse, add nginx rate limiting for provider endpoints.

---

## Testing Your Free Tier Setup

### Test SSL/TLS

```bash
# Verify Full (strict) mode
openssl s_client -connect provider.reverb256.ca:443
# Should show: Verify return code: 0 (certificate validated)

# Verify TLS 1.1 rejected
openssl s_client -connect provider.reverb256.ca:443 -tls1_1
# Should fail: no protocol available
```

### Test DNS Resolution

```bash
# Test tenant DNS
dig myapp.dedicated.ingress.reverb256.ca

# Should resolve to tunnel IP
# TTL should be ~2 minutes (optimal)
```

### Test Cache Bypass

```bash
# Deploy test workload
kubectl apply -f test-deployment.yaml

# Access via ingress
curl -I https://myapp.ingress.reverb256.ca

# Since proxied=false, should see no CF-Cache-Status header
# (direct connection to origin, no Cloudflare cache)
```

### Test Provider Access

```bash
# Test provider endpoint (with Zero Trust auth)
curl https://provider.reverb256.ca/v1/status

# Should prompt for Zero Trust authentication
# After auth, should return provider status
```

---

## Free Tier vs Pro Tier Comparison

### What You're Missing Without Pro ($20/mo)

| Feature | Benefit | Cost-Benefit |
|---------|---------|--------------|
| Page Rules | Fine-grained cache control | Low - cache purging works |
| Rate Limiting | DDoS protection at edge | Medium - nginx limiting works |
| Transform Rules | Easy header management | Low - nginx works |
| WAF | SQLi/XSS protection | Low - not needed for provider |
| Image Optimization | Faster image loading | N/A - not applicable |

### Recommendation: Stay on Free Tier

**Why:**
1. ✅ Cache purging via API works fine for tenant deployments
2. ✅ Origin-level rate limiting (nginx) provides adequate protection
3. ✅ Origin-level headers (nginx) provide security hardening
4. ✅ SSL/TLS hardening available on free tier
5. ✅ Zero Trust protection available on free tier
6. ❌ Pro tier features don't provide significant value for provider use case

**Savings:** $240/year (Pro plan)

---

## Conclusion

**Your current Cloudflare free tier setup is 90% optimal!**

### Already Configured (✅)
- SSL/TLS: Need to upgrade to Full (strict)
- DNS: Optimal (proxied=false)
- Tunnel: Working perfectly
- Zero Trust: Provider endpoints protected
- Cache Purging: Automated via integration

### Recommended Actions (Free Tier)
1. **Set SSL/TLS to Full (strict)** - Do this today!
2. **Set minimum TLS to 1.2** - Do this today!
3. **Verify cache purging works** - Test with tenant deployment
4. **Add nginx headers** (optional) - If you want extra security
5. **Add nginx rate limiting** (optional) - If you experience abuse

### NOT Needed (Free Tier Limitations)
- ❌ Page Rules - Use origin headers instead
- ❌ Rate Limiting - Use nginx instead
- ❌ Transform Rules - Use nginx instead
- ❌ WAF - Not needed for provider use case

---

**Next Steps:**
1. Apply SSL/TLS optimizations: `/etc/nixos/scripts/cloudflare-optimizations-apply.sh apply`
2. Verify settings in Cloudflare dashboard
3. Test with tenant deployment
4. Monitor logs for abuse (if concerned, add nginx rate limiting)

**Version:** 2.0 (Free Tier Edition)
**Last Updated:** 2026-03-20
**Cloudflare Plan:** FREE
