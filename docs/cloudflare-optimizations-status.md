# Cloudflare Optimizations Status Report

**Generated:** 2026-03-20
**Domain:** reverb256.ca
**Zone ID:** 9062487114ef5404de8de6689cb54895

---

## Current Configuration

### ✅ Already Configured

| Setting | Value | Status |
|---------|-------|--------|
| DNS Record | `*.ingress.reverb256.ca` → Cloudflare Tunnel | ✅ Active |
| Tunnel ID | `e67aedf0-a025-4231-9ee4-3fa6887c2d21` | ✅ Active |
| Zero Trust | Provider endpoints protected | ✅ Active |
| QUIC Protocol | Enabled for faster connections | ✅ Active |
| Connection Pooling | 100 connections, 90s timeout | ✅ Active |

### ⚠️ Needs Attention

| Setting | Current | Recommended | Priority |
|---------|---------|-------------|----------|
| SSL/TLS Mode | Unknown | Full (strict) | ⭐⭐⭐ HIGH |
| Minimum TLS | Unknown | 1.2 or higher | ⭐⭐⭐ HIGH |
| Cache Bypass | Not configured | Bypass for `*.ingress.reverb256.ca` | ⭐⭐⭐ HIGH |
| Rate Limiting | Not configured | 100 req/min for provider | ⭐⭐ MEDIUM |
| Security Headers | Not configured | X-Frame-Options, etc. | ⭐ LOW |

---

## Discovered Configuration

### DNS Records

```
*.ingress.reverb256.ca
  Type: CNAME
  Target: 8dbfc488-5b3a-4ac5-9624-1d31e3682e4e.cfargotunnel.com
  TTL: 1 (auto)
  Proxied: false (direct DNS, not cached)
```

**Analysis:** This is good! The `proxied: false` setting means:
- DNS resolves directly to the tunnel
- No Cloudflare proxy caching
- Faster connection to tenant deployments
- However, application-level caching may still occur

### Provider Endpoints (Zero Trust Protected)

- `provider.reverb256.ca` → Protected by Zero Trust (email: j_kroeker@reverb256.ca)
- `grpc.provider.reverb256.ca` → Protected by Zero Trust
- `status.provider.reverb256.ca` → Public dashboard
- `akash.reverb256.ca` → Public status page

---

## Manual Steps Required

### 1. Cache Bypass Page Rules (⭐⭐⭐ CRITICAL)

**Why:** Prevents stale content for tenant deployments

**Steps:**
1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/rules/page-rules
2. Click "Create Page Rule"
3. Rule #1:
   - **URL:** `*.ingress.reverb256.ca/*`
   - **Settings:** Cache Level → Bypass
4. Rule #2:
   - **URL:** `*.dedicated.ingress.reverb256.ca/*`
   - **Settings:** Cache Level → Bypass

**Expected Result:**
```bash
# Test cache bypass
curl -I https://myapp.ingress.reverb256.ca

# Should see: CF-Cache-Status: BYPASS
# If you see: CF-Cache-Status: HIT or MISS → Not working
```

### 2. SSL/TLS Configuration (⭐⭐⭐ HIGH)

**Why:** Ensures secure connections to provider endpoints

**Steps:**
1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/ssl/tls-configuration
2. Set: **Overview** → "Full (strict)"
3. Set: **Minimum TLS Version** → "1.2"

**Expected Result:**
- Provider endpoints validate origin certificates
- Prevents man-in-the-middle attacks
- gRPC connections require valid TLS 1.2+

### 3. Rate Limiting (⭐⭐ MEDIUM, Pro Plan Required)

**Why:** Protects provider API from DoS attacks

**Steps:**
1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/security/rate-limiting-rules
2. Create Rule #1: Protect Provider API
   - **When:** Incoming request matches `provider.reverb256.ca/*`
   - **Then:** Limit to 100 requests per minute
   - **Action:** Challenge (CAPTCHA)
3. Create Rule #2: Protect gRPC
   - **When:** Incoming request matches `grpc.provider.reverb256.ca/*`
   - **Then:** Limit to 50 requests per minute
   - **Action:** Block

**Note:** Requires Cloudflare Pro plan or higher

### 4. Security Headers (⭐ LOW, Optional)

**Why:** Adds security hardening for tenant apps

**Steps:**
1. Go to: https://dash.cloudflare.com/9062487114ef5404de8de6689cb54895/rules/transform
2. Create Transform Rule:
   - **When:** Hostname matches `*.ingress.reverb256.ca/*` OR `*.dedicated.ingress.reverb256.ca/*`
   - **Then:**
     - Set Response Header: `X-Frame-Options = "SAMEORIGIN"`
     - Set Response Header: `X-Content-Type-Options = "nosniff"`
     - Set Response Header: `X-XSS-Protection = "1; mode=block"`
     - Set Response Header: `Referrer-Policy = "strict-origin-when-cross-origin"`

---

## Automated Steps (via Script)

### Apply SSL/TLS Optimizations

```bash
# Set API token
export CLOUDFLARE_API_TOKEN="cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5"

# Run optimization script
/etc/nixos/scripts/cloudflare-optimizations-apply.sh apply
```

**What This Does:**
- ✅ Verifies API token is valid
- ✅ Sets SSL/TLS to "Full (strict)"
- ✅ Sets minimum TLS version to 1.2
- ✅ Generates configuration report
- ⚠️  Shows manual steps for page rules and rate limiting

### Check Current Status

```bash
export CLOUDFLARE_API_TOKEN="cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5"
/etc/nixos/scripts/cloudflare-optimizations-apply.sh check
```

---

## Token Storage

### Current Token (Unencrypted - DO NOT COMMIT)

```
cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5
```

**Token Details:**
- ID: `c5f707f4f063584dbfd3cffd928303b9`
- Status: Active
- Expires: 2027-04-01
- Permissions: Zone Read + SSL/DNS/Settings Edit

### Secure Storage (Recommended)

To store the token securely with agenix:

```bash
# Encrypt the token
cd /etc/nixos
agenix -e secrets/cloudflare-api-token.age

# Paste the token (just the string, no JSON):
# cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5

# Add to agenix secrets registry
# Edit modules/system/agenix-secrets-registry.nix:
# Under "cloud" section, add:
#   cloudflare-api-token = {
#     file = "${inputs.self}/secrets/cloudflare-api-token.age";
#     mode = "400";
#     owner = "root";
#     group = "root";
#   };

# Deploy
just deploy
```

**After Deployment:**
```bash
# Token available at /run/agenix/cloudflare-api-token
export CLOUDFLARE_API_TOKEN=$(cat /run/agenix/cloudflare-api-token)
/etc/nixos/scripts/cloudflare-optimizations-apply.sh apply
```

---

## Testing Checklist

### After Applying Optimizations

- [ ] **SSL/TLS: Full (strict)**
  ```bash
  openssl s_client -connect provider.reverb256.ca:443
  # Should see: Verify return code: 0
  ```

- [ ] **Minimum TLS 1.2**
  ```bash
  openssl s_client -connect provider.reverb256.ca:443 -tls1_1
  # Should fail (TLS 1.1 rejected)
  ```

- [ ] **Cache Bypass Working**
  ```bash
  curl -I https://myapp.ingress.reverb256.ca
  # Should see: CF-Cache-Status: BYPASS
  ```

- [ ] **DNS Resolution**
  ```bash
  dig myapp.dedicated.ingress.reverb256.ca
  # Should resolve to tunnel IP
  ```

- [ ] **Provider Endpoints Accessible**
  ```bash
  curl https://provider.reverb256.ca/v1/status
  # Should return provider status (with Zero Trust auth)
  ```

---

## Next Steps

1. **Immediate (Today):**
   - [ ] Encrypt API token with agenix
   - [ ] Add to secrets registry
   - [ ] Deploy to all hosts
   - [ ] Apply SSL/TLS optimizations via script

2. **Soon (This Week):**
   - [ ] Configure cache bypass page rules (dashboard)
   - [ ] Verify SSL/TLS settings (dashboard)
   - [ ] Test cache bypass with tenant deployment

3. **Later (If Pro Plan Available):**
   - [ ] Configure rate limiting rules
   - [ ] Add security headers via Transform Rules
   - [ ] Set up analytics dashboard

---

## Troubleshooting

### Issue: API Token Not Working

**Symptoms:** Script shows "API token is invalid or expired"

**Diagnosis:**
```bash
# Verify token manually
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json"
```

**Solution:** Generate new token at https://dash.cloudflare.com/profile/api-tokens

### Issue: Page Rules Not Working

**Symptoms:** `CF-Cache-Status: HIT` instead of `BYPASS`

**Diagnosis:**
```bash
curl -I https://myapp.ingress.reverb256.ca | grep CF-Cache-Status
```

**Solution:**
1. Check page rule order (more specific rules first)
2. Verify URL pattern matches exactly
3. Clear Cloudflare cache after creating rule

### Issue: SSL/TLS Won't Update

**Symptoms:** Dashboard shows different setting than API returns

**Solution:** Some settings require Pro plan. Check your plan tier at https://dash.cloudflare.com

---

## Related Documentation

- **Implementation Guide:** `docs/cloudflare-optimizations-for-akash.md`
- **Akash Integration:** `docs/akash-cloudflare-integration.md`
- **Optimization Script:** `scripts/cloudflare-optimizations-apply.sh`
- **Cloudflared Module:** `modules/services/cloudflared.nix`

---

**Version:** 1.0
**Last Updated:** 2026-03-20
**API Token Expires:** 2027-04-01
