# Cloudflare Optimizations for Akash Provider

## Overview

This document outlines Cloudflare optimizations to improve reliability, performance, and security for the Akash Network provider deployment on `reverb256.ca`.

**Provider Architecture:**
- Domain: `reverb256.ca`
- Zone ID: `9062487114ef5404de8de6689cb54895`
- Provider Endpoint: `provider.reverb256.ca` (Zero Trust protected)
- Tenant Ingress: `*.ingress.reverb256.ca` (public)
- Dedicated DNS: `*.dedicated.ingress.reverb256.ca` (auto-created, public)

---

## Priority 1: DNS Settings (Already Configured ✅)

### Tenant DNS TTL
**Status:** Already optimized in `akash-cloudflare-integration.nix`
```bash
# Current setting: TTL=120 (2 minutes)
--data '{"type":"A","name":"$dns_name","content":"$ingress_ip","ttl":120,"proxied":false}'
```

**Why This Matters:**
- Low TTL (120s) = Fast DNS propagation when tenants deploy
- Tenants can access their deployments within 2 minutes
- Reduces support burden from DNS caching issues

**No Action Needed** - Already optimal!

---

## Priority 2: Cache Rules (Recommended ⚠️)

### Problem: Cloudflare Cache Can Stale Tenant Content

When tenants deploy updates, Cloudflare's cache may serve old content for up to 30 minutes (default browser cache TTL).

### Solution: Page Rules for Cache Bypass

**Create Page Rule via Cloudflare Dashboard:**

1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/rules/page-rules

2. Create Rule #1: Bypass Cache for Tenant Ingress
   ```
   URL Pattern: *.ingress.reverb256.ca/*
   Settings:
   - Cache Level: Bypass
   - Disable Performance
   ```

3. Create Rule #2: Bypass Cache for Dedicated DNS
   ```
   URL Pattern: *.dedicated.ingress.reverb256.ca/*
   Settings:
   - Cache Level: Bypass
   - Disable Performance
   ```

**Why This Matters:**
- Tenants deploying web apps see updates immediately
- No stale cached content after deployments
- Better tenant experience = better provider reputation

**Alternative: Use Transform Rules (More Flexible)**

If you have Cloudflare Pro or higher, use Transform Rules instead:

```yaml
# Transform Rule: Ingress Cache Bypass
When:
  - Hostname matches wildcard: *.ingress.reverb256.ca
  - OR Hostname matches wildcard: *.dedicated.ingress.reverb256.ca
Then:
  - Set Cache Status: Bypass
```

---

## Priority 3: SSL/TLS Optimization (Recommended ⚠️)

### Current Setting Check

**Verify in Cloudflare Dashboard:**
1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/ssl/tls-configuration
2. Recommended setting: **Full (strict)**

**Why Full (strict):**
- Validates origin server certificates
- Prevents man-in-the-middle attacks
- Required for gRPC provider endpoint

**For Provider Endpoints:**
- `provider.reverb256.ca` → Full (strict) - Zero Trust already enforces this
- `grpc.provider.reverb256.ca` → Full (strict) - gRPC requires valid certs

**For Tenant Endpoints:**
- `*.ingress.reverb256.ca` → Full - Allow self-signed tenant certs
- `*.dedicated.ingress.reverb256.ca` → Full - Allow self-signed tenant certs

### Minimum TLS Version

**Set to: TLS 1.2 or higher**
1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/ssl/tls-configuration
2. Set: Minimum TLS Version = **1.2**

**Why:**
- TLS 1.0/1.1 deprecated and insecure
- Modern clients support TLS 1.2+
- Akash provider uses gRPC which requires TLS 1.2+

---

## Priority 4: Rate Limiting (Recommended ⚠️)

### Problem: DoS Attacks on Provider Bid Engine

The provider's REST API (`provider.reverb256.ca`) could be targeted by:
- Excessive bid requests (resource exhaustion)
- Brute force attacks on Zero Trust login
- Scraping attacks on provider status endpoint

### Solution: Rate Limiting Rule

**Create Rate Limit Rule:**

1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/security/rate-limiting-rules

2. Create Rule: Protect Provider API
   ```
   When:
     - Incoming request matches: provider.reverb256.ca/*
     - OR Incoming request matches: grpc.provider.reverb256.ca/*

   Then:
     - Limit to: 100 requests per minute
     - Action: Challenge (CAPTCHA)
     - Period: 1 minute
   ```

3. Create Rule: Stricter Limit for Bid Engine
   ```
   When:
     - Incoming request matches: provider.reverb256.ca/v1/bids/*

   Then:
     - Limit to: 20 requests per minute
     - Action: Block
     - Period: 1 minute
   ```

**Why This Matters:**
- Prevents resource exhaustion on provider NodePorts
- Protects against automated bidding bots
- Ensures fair access for legitimate tenants

**Note:** Zero Trust already provides some protection, but rate limiting adds defense-in-depth.

---

## Priority 5: Security Headers (Recommended ⚠️)

### Add Security Headers via Transform Rules

**Create Transform Rule:**

1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/rules/transform

2. Create Rule: Modify Response Headers
   ```
   When:
     - Incoming request matches: *.ingress.reverb256.ca/*
     - OR Incoming request matches: *.dedicated.ingress.reverb256.ca/*

   Then:
     - Set Response Header: X-Frame-Options = "SAMEORIGIN"
     - Set Response Header: X-Content-Type-Options = "nosniff"
     - Set Response Header: X-XSS-Protection = "1; mode=block"
     - Set Response Header: Referrer-Policy = "strict-origin-when-cross-origin"
   ```

**Why This Matters:**
- Prevents clickjacking attacks on tenant apps
- Stops MIME-type sniffing vulnerabilities
- Adds XSS protection for tenant web apps
- Improves provider security posture

---

## Priority 6: Analytics and Monitoring (Optional 📊)

### Cloudflare Analytics Dashboard

**Create Custom Dashboard:**

1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/analytics/dashboard

2. Add Widgets:
   - **Top 10 Tenant Domains** (by request count)
   - **HTTP Error Rate** (4xx/5xx for *.ingress.reverb256.ca)
   - **Threat Traffic** (blocked requests)
   - **Bandwidth Usage** (by tenant)
   - **Cache Hit Rate** (should be 0% if bypass enabled)

3. Set Up Alerts:
   - Error rate > 5% for 5 minutes
   - Threat traffic spike > 100 requests/minute
   - Bandwidth anomaly detection

**Why This Matters:**
- Identify problematic tenants
- Detect attacks early
- Capacity planning for bandwidth
- Validate cache bypass is working

---

## Priority 7: DNS Zone Settings (One-Time Setup 🔧)

### Verify Zone Configuration

**Check at:** https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/dns

**Recommended Settings:**

1. **DNSSEC:** Enable if available
   - Prevents DNS cache poisoning attacks
   - Adds cryptographic signatures to DNS records

2. **CNAME Flattening:** Enable
   - Automatically resolves CNAME chains to A records
   - Reduces DNS lookup latency

3. **Universal SSL:** Already enabled ✅
   - Free SSL certificates for all subdomains
   - Automatic renewal

4. **Always Online:** Disable for provider endpoints
   - Don't show cached page if provider is down
   - Better to fail fast than show stale data

---

## Priority 8: Web Application Firewall (WAF) (Optional 🛡️)

### Enable WAF for Provider Endpoints

**Create WAF Rule:**

1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/security/waf

2. Create Rule: Protect Provider API
   ```
   When:
     - Hostname: provider.reverb256.ca
     - OR Hostname: grpc.provider.reverb256.ca

   Then:
     - Enable all Managed Rulesets
     - Block: SQL injection, XSS, authentication attacks
   ```

3. Create Rule: Allow Legitimate gRPC Traffic
   ```
   When:
     - Hostname: grpc.provider.reverb256.ca
     - User Agent contains: "grpc-go"

   Then:
     - Skip all WAF checks
   ```

**Why This Matters:**
- Blocks common attack patterns
- Protects against zero-day vulnerabilities
- Minimal false positives with proper tuning

**Note:** WAF is only available with Cloudflare Pro or higher plans.

---

## Priority 9: Origin Configuration (Already Optimized ✅)

### Current Cloudflare Tunnel Settings

**In `/etc/nixos/modules/services/cloudflared.nix`:**

```nix
originRequest = {
  connectTimeout = "30s";      # ✅ Good for gRPC
  tlsTimeout = "10s";          # ✅ Fast TLS handshake
  tcpKeepAlive = 30;           # ✅ Detect dead connections
  keepAliveConnections = 100;  # ✅ Connection pooling
  keepAliveTimeout = 90;       # ✅ Reuse connections
};
quicEnabled = true;            # ✅ 30-50% faster
```

**No Changes Needed** - Already optimized for provider use case!

---

## Priority 10: Failover and Redundancy (Future Consideration 🔮)

### Multiple Provider Instances

**If you deploy multiple provider instances:**

1. **Load Balancing**
   - Create Cloudflare Load Balancer
   - Health checks on `/status` endpoint
   - Weighted routing based on GPU availability

2. **Geographic Routing**
   - Direct tenants to nearest region
   - Reduce latency for international tenants

3. **DNS Failover**
   - Automatic failover if provider instance fails
   - Zero downtime deployments

**Current Setup:** Single provider instance = not applicable yet.

---

## Implementation Checklist

### Immediate Actions (High Priority)
- [ ] Verify SSL/TLS setting is "Full (strict)"
- [ ] Set minimum TLS version to 1.2
- [ ] Create page rules for cache bypass on `*.ingress.reverb256.ca`
- [ ] Create page rules for cache bypass on `*.dedicated.ingress.reverb256.ca`

### Soon (Medium Priority)
- [ ] Set up rate limiting for provider endpoints
- [ ] Add security headers via Transform Rules
- [ ] Create analytics dashboard for tenant traffic

### Later (Low Priority)
- [ ] Enable DNSSEC
- [ ] Configure WAF rules (if Pro plan)
- [ ] Set up custom alerts and notifications

---

## Testing Your Optimizations

### Test Cache Bypass

```bash
# Deploy test workload
kubectl apply -f test-deployment.yaml

# Access via ingress
curl -I https://myapp.ingress.reverb256.ca

# Should see: CF-Cache-Status: BYPASS
# If you see: CF-Cache-Status: HIT or MISS → Cache bypass not working
```

### Test SSL/TLS

```bash
# Check provider certificate
openssl s_client -connect provider.reverb256.ca:443 -servername provider.reverb256.ca

# Should see: Verify return code: 0 (verification successful)
# If you see: certificate verify failed → SSL misconfigured
```

### Test Rate Limiting

```bash
# Send 20 requests in 10 seconds
for i in {1..20}; do
  curl -s https://provider.reverb256.ca/v1/status &
done
wait

# Should see: 429 Too Many Requests (after rate limit hit)
```

---

## Troubleshooting

### Issue: Tenant DNS Not Resolving

**Symptoms:** `dig myapp.dedicated.ingress.reverb256.ca` returns NXDOMAIN

**Diagnosis:**
```bash
# Check DNS watcher logs
journalctl -u akash-cloudflare-dns-watcher -f

# Check if DNS record exists in Cloudflare
curl -s "https://api.cloudflare.com/client/v4/zones/9062487114ef5404de8de6689cb54895/dns_records?name=myapp.dedicated.ingress.reverb256.ca" \
  -H "Authorization: Bearer $(cat /run/agenix/cloudflared-token)" | jq
```

**Solution:** Wait 120 seconds (TTL) + DNS propagation time

### Issue: Stale Content After Tenant Deployment

**Symptoms:** Tenant sees old version of their app

**Diagnosis:**
```bash
# Check cache status
curl -I https://myapp.ingress.reverb256.ca | grep CF-Cache-Status
```

**Solution:** Add cache bypass page rule (see Priority 2)

### Issue: Provider API Slow

**Symptoms:** High latency on `provider.reverb256.ca`

**Diagnosis:**
```bash
# Check tunnel metrics
curl http://10.1.1.110:54162/metrics | grep tunnel

# Check origin connection timeouts
journalctl -u cloudflared-tunnel -n 50
```

**Solution:** Increase `connectTimeout` in cloudflared.nix

---

## Conclusion

**Current State:** Your Akash Cloudflare integration is already well-optimized with:
- ✅ Fast DNS propagation (120s TTL)
- ✅ Direct DNS routing (no proxy for tenant endpoints)
- ✅ Zero Trust protection for provider endpoints
- ✅ QUIC protocol for faster tunnel connections
- ✅ Connection pooling and keep-alive

**Recommended Next Steps:**
1. **Cache bypass page rules** - Highest impact on tenant experience
2. **SSL/TLS verification** - Security best practice
3. **Rate limiting** - Protect against DoS attacks

**Expected Benefits:**
- Better tenant experience (no stale content)
- Improved security posture
- Reduced support burden
- Protection against common attacks

---

**Version:** 1.0
**Last Updated:** 2026-03-20
**Related Docs:**
- `docs/akash-cloudflare-integration.md` - Integration usage guide
- `modules/services/akash-cloudflare-integration.nix` - Implementation
- `modules/services/cloudflared.nix` - Tunnel configuration
