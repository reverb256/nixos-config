# Cloudflare Zero Trust Setup Guide

**Provider**: Reverb256 Akash Provider
**Last Updated**: 2026-03-19
**Purpose**: Secure Akash provider endpoints with Zero Trust authentication

---

## Overview

**What You're Securing**:
- ✅ **Provider bid engine** (`provider.reverb256.ca`) - RESTRICTED
- ✅ **Provider gRPC** (`grpc.provider.reverb256.ca`) - RESTRICTED
- ✅ **Tenant deployments** (`*.ingress.reverb256.ca`) - PUBLIC (no auth needed)

**Why**:
- Prevent unauthorized access to your provider management
- Add professional security for potential tenants
- Protect bid/lease management endpoints

---

## Step 1: Access Cloudflare Zero Trust Dashboard

### Navigate to Zero Trust

```
1. Go to: https://dash.cloudflare.com
2. Select your domain: reverb256.ca
3. Click: "Zero Trust" (left sidebar)
4. Go to: Access → Applications
```

---

## Step 2: Create Zero Trust Application

### Click "Add an application"

#### Application Settings

**Basic Information**:
```
Application Name: Akash Provider - Reverb256
Session Duration: 24h (recommended)
```

**Identity Providers** (Select one or more):

**Option 1: Email (Magic Link)** - RECOMMENDED
```
✅ Email
  - Send a 6-digit PIN via email
  - No password needed
  - Works with any email address
```

**Option 2: GitHub (OAuth)**
```
✅ GitHub
  - Login with GitHub account
  - Familiar for developers
  - Easy to manage
```

**Option 3: Google (OAuth)**
```
✅ Google
  - Login with Google account
  - Widely supported
  - Good for tenants
```

**Recommendation**: Enable **Email + GitHub** (flexible options)

---

## Step 3: Configure Access Policies

### Policy 1: Provider Owner (Required)

**Settings**:
```
Policy Name: Provider Owner
Action: Allow
```

**Conditions** (Choose ONE):

**Option A: Email Authorization**
```
Email:
  - your-email@example.com
  - your-email@gmail.com
  (Add all your email addresses)
```

**Option B: GitHub Authorization**
```
GitHub:
  - Your GitHub username
  - Your GitHub organization
```

**Option C: Email Domain** (for team access)
```
Email Domain:
  - reverb256.ca
  - example.com
  (Anyone with @reverb256.ca email can access)
```

**Recommendation**: Start with **your email address**

---

### Policy 2: Authorized Tenants (Optional)

**Settings**:
```
Policy Name: Authorized Tenants
Action: Allow
Precedence: Below "Provider Owner" policy
```

**Conditions**:

**Option A: Specific Tenant Emails**
```
Email:
  - tenant1@example.com
  - tenant2@theircompany.com
  - tenant3@university.edu
```

**Option B: GitHub Users**
```
GitHub:
  - tenant-github-username-1
  - tenant-github-username-2
```

**Option C: Cloudflare Access Group** (ADVANCED)
```
1. Create Access Group first: "akash-tenants"
2. Add users to group
3. Use group in policy:
   Group: akash-tenants
```

**Recommendation**: Skip for now, add later when you have specific tenants

---

### Policy 3: Default Fallback (Optional)

**Settings**:
```
Policy Name: Require Approval
Action: Allow (with approval)
Precedence: Last policy (catch-all)
```

**Conditions**:
```
Anyone (default)
```

**Approval Settings**:
```
Require approval from:
  - your-email@example.com

Approval duration:
  - 1 hour (temporary access)

Reason required:
  - Yes (ask requester why they need access)
```

**Recommendation**: Enable this to catch unauthorized access attempts

---

## Step 4: Configure Application URLs

### Add Your Provider Endpoints

**Settings**:
```
Application Type: Self-Hosted
Domain: reverb256.ca
```

**Add URLs** (one per line):
```
https://provider.reverb256.ca
https://grpc.provider.reverb256.ca
```

**Important**: DO NOT add `*.ingress.reverb256.ca` (tenant deployments should remain public)

---

## Step 5: Test Zero Trust Access

### Test 1: Access Provider Endpoint (Should Require Auth)

```bash
# Try accessing provider endpoint (should show login page)
curl -I https://provider.reverb256.ca

# Expected response:
# HTTP/2 403
# Location: https://your-cloudflare-access.dash/
# (Redirects to Zero Trust login)
```

**Manual Test**:
1. Open browser: `https://provider.reverb256.ca`
2. Should see: **"Access Denied"** or **Zero Trust login page**
3. Enter your email → Receive magic link
4. Click magic link → **Access granted!**

### Test 2: Access Tenant Endpoint (Should Work, No Auth)

```bash
# Try accessing tenant ingress (should work directly)
curl -I https://test.ingress.reverb256.ca

# Expected response:
# HTTP/2 200
# (No redirect, direct access)
```

**Manual Test**:
1. Open browser: `https://test.ingress.reverb256.ca`
2. Should see: **Direct access** (no login required)

---

## Step 6: Deploy Configuration

### Update NixOS Configuration

Configuration already updated in:
```
/etc/nixos/hosts/zephyr/configuration.nix
```

**Changes made**:
- ✅ Added `accessPolicy` to provider endpoints
- ✅ Kept tenant endpoints public (no `accessPolicy`)

### Deploy

```bash
# Validate configuration
nix flake check

# Build and test
nixos-rebuild test --fast

# If successful, switch permanently
nixos-rebuild switch

# Or deploy to all hosts
just deploy
```

### Restart Cloudflared

```bash
# Restart cloudflared to apply changes
systemctl restart cloudflared-tunnel

# Check status
systemctl status cloudflared-tunnel

# View logs
journalctl -u cloudflared-tunnel -f
```

---

## Step 7: Verify Zero Trust is Working

### Check 1: Provider Endpoints Require Auth

```bash
# Should require authentication
curl -v https://provider.reverb256.ca 2>&1 | grep -E "(403|Location|access)"

# Expected output:
# < HTTP/2 403
# < Location: https://your-cloudflare-access.dash/
```

### Check 2: Tenant Endpoints Are Public

```bash
# Should work without authentication
curl -v https://test.ingress.reverb256.ca 2>&1 | grep -E "(200|403)"

# Expected output:
# < HTTP/2 200
# (No 403, no redirect)
```

### Check 3: Test with Your Email

1. Open browser: `https://provider.reverb256.ca`
2. Click: **"Email a one-time PIN"**
3. Enter: `your-email@example.com`
4. Check email → Enter 6-digit PIN
5. **Success!** You should see provider homepage

---

## Advanced Configuration

### Multiple Provider Owners

**Scenario**: You have a team managing the provider

**Solution**: Use **Email Domain** policy

```
Policy Name: Provider Team
Action: Allow
Conditions:
  Email Domain: reverb256.ca
```

**Result**: Anyone with `@reverb256.ca` email can access

### Temporary Access for Support

**Scenario**: Need to grant temporary access to Akash support

**Solution**: Use **One-Time PIN** with expiration

```
Policy Name: Temporary Support Access
Action: Allow (with time restriction)
Conditions:
  Email: support@akash.network
  Valid for: 1 hour
```

**Result**: Support can access for 1 hour, then automatically revoked

### IP Whitelist (Optional)

**Scenario**: Only allow access from specific IP ranges

**Solution**: Add **IP policy** before email policy

```
Policy Name: IP Whitelist
Action: Allow
Conditions:
  IP: 10.1.1.0/24 (your home network)
  OR
  IP: 203.0.113.0/24 (your office)
```

**Result**: No authentication needed from trusted IPs

---

## Troubleshooting

### Issue 1: "Access Denied" Even After Login

**Problem**: Authenticated but still denied

**Solutions**:
1. Check email matches policy exactly
2. Check GitHub username is correct (case-sensitive)
3. Check policy precedence (owner policy must be first)

### Issue 2: Tenant Deployments Require Auth

**Problem**: `*.ingress.reverb256.ca` asking for login

**Solution**:
1. Check cloudflared config (should have NO `accessPolicy` for tenant endpoints)
2. Restart cloudflared: `systemctl restart cloudflared-tunnel`

### Issue 3: Provider Not Accessible After Setup

**Problem**: Can't access `provider.reverb256.ca` at all

**Solutions**:
1. Check cloudflared logs: `journalctl -u cloudflared-tunnel -n 50`
2. Check tunnel is active: `cloudflared tunnel list`
3. Check ingress rules in config
4. Verify DNS records point to tunnel

### Issue 4: Magic Link Not Received

**Problem**: No email with magic link

**Solutions**:
1. Check spam folder
2. Verify email address is correct
3. Try alternative auth method (GitHub, Google)
4. Check Cloudflare Access logs in dashboard

---

## Security Best Practices

### ✅ DO

- **Enable multiple auth methods** (Email + GitHub)
- **Use email domain** for team access
- **Require approval** for unknown users
- **Regularly review access logs** in Cloudflare dashboard
- **Rotate auth methods** periodically

### ❌ DON'T

- **Don't use "Anyone" policy** without approval
- **Don't share your magic links** (one-time use only)
- **Don't skip authentication** for provider endpoints
- **Don't forget to revoke access** for former team members

---

## Monitoring & Logging

### View Access Logs

```
Cloudflare Dashboard → Zero Trust → Logs → Activity
```

**What to monitor**:
- Failed access attempts (unauthorized users trying to access)
- Successful logins (who accessed your provider)
- Geographic anomalies (access from unusual locations)
- Time-based patterns (access at odd hours)

### Set Up Alerts

```
Cloudflare Dashboard → Zero Trust → Configuration → Notifications
```

**Alerts to configure**:
- **Failed access attempts** > 10 in 1 hour
- **New user** accessing provider
- **Access from** new geographic region
- **Approval request** received

---

## Configuration Reference

### Complete cloudflared Configuration

```nix
# /etc/nixos/hosts/zephyr/configuration.nix
{
  services.cloudflared-tunnel = {
    enable = true;
    tunnelId = "e67aedf0-a025-4231-9ee4-3fa6887c2d21";

    # Enable QUIC protocol
    quicEnabled = true;

    # Origin request configuration (performance tuning)
    originRequest = {
      connectTimeout = "30s";
      tlsTimeout = "10s";
      tcpKeepAlive = 30;
      keepAliveConnections = 100;
      keepAliveTimeout = 90;
    };

    # Ingress rules with Zero Trust
    ingressRules = [
      # Provider bid engine - RESTRICTED
      {
        hostname = "provider.reverb256.ca";
        service = "https://10.1.1.120:30843";
        accessPolicy = "your-email@example.com";  # Replace!
      }
      # Provider gRPC - RESTRICTED
      {
        hostname = "grpc.provider.reverb256.ca";
        service = "https://10.1.1.120:30844";
        accessPolicy = "your-email@example.com";  # Replace!
      }
      # Tenant deployments - PUBLIC
      {
        hostname = "*.ingress.reverb256.ca";
        service = "http://10.1.1.120:30080";
        # No accessPolicy = Public
      }
      # Bare ingress domain - PUBLIC
      {
        hostname = "ingress.reverb256.ca";
        service = "http://10.1.1.120:30080";
        # No accessPolicy = Public
      }
      # Catch-all: Return 404
      {
        service = "http_status:404";
      }
    ];

    # Metrics for monitoring
    metricsPort = 54162;
  };
}
```

---

## Next Steps

### Immediate (Today)
1. ✅ Create Zero Trust application in Cloudflare dashboard
2. ✅ Configure email + GitHub auth
3. ✅ Add your email to provider owner policy
4. ✅ Deploy NixOS configuration
5. ✅ Test access to provider endpoints

### This Week
1. 🔄 Monitor access logs for anomalies
2. 🔄 Add team members if needed
3. 🔄 Set up alerts for failed access attempts
4. 🔄 Document access procedures for tenants

### Future Enhancements
1. 📋 Configure tenant-specific access policies
2. 📋 Set up IP whitelisting for trusted locations
3. 📋 Integrate with SSO (if using enterprise auth)
4. 📋 Configure geographic access policies

---

## Support & Documentation

**Cloudflare Zero Trust Documentation**:
- Getting Started: https://developers.cloudflare.com/cloudflare-one/tutorials/
- Access Policies: https://developers.cloudflare.com/cloudflare-one/policies/access/
- Application Configuration: https://developers.cloudflare.com/cloudflare-one/applications/

**Akash Provider Documentation**:
- Provider Setup: https://docs.akash.network/providers
- Provider Security: https://docs.akash.network/providers/security-best-practices

---

**Status**: ✅ Configuration complete, ready for deployment
**Time to complete**: ~30 minutes
**Security impact**: HIGH (professional security for your provider)
