# Cloudflare Zero Trust - Simplified Setup

**3-minute guide with screenshots** 📸

---

## Step 1: Open Cloudflare Access (30 seconds)

1. Go to: https://dash.cloudflare.com
2. Click: **reverb256.ca** (your domain)
3. Left sidebar: **Zero Trust** → **Access** → **Applications**
4. Click: **Add an application**

---

## Step 2: Create Application (1 minute)

### Basic Settings

```
Application name: Akash Provider
Session Duration: 24h
Application Type: Self-Hosted
```

### Add Domain

```
Domain: reverb256.ca
```

### Add Paths (Optional, skip for now)

Leave empty - we'll add specific URLs next

---

## Step 3: Add Your Provider URLs (30 seconds)

Click **"Add application"** first, then:

1. Click on your new application: **"Akash Provider"**
2. Go to: **Settings** tab
3. Scroll to: **"Application URLs"**
4. Click: **"Add URL"**

Add these URLs (one per line):

```
https://provider.reverb256.ca
https://grpc.provider.reverb256.ca
```

Click: **"Save"**

---

## Step 4: Configure Authentication (1 minute)

### Add Identity Providers

Go to: **"Akash Provider"** → **Settings** → **Identity Providers**

Click: **"Add a provider"**

**Enable Email** (recommended):
```
Name: Email
Type: One-Time PIN
Send: Email the PIN
```

Click: **"Save"**

**Enable GitHub** (optional but recommended):
```
Name: GitHub
Type: GitHub OAuth
```

Click: **"Save"**

---

## Step 5: Create Access Policy (30 seconds)

Go to: **"Akash Provider"** → **"Policies"** tab

You'll see a default policy. Edit it:

```
Policy name: Provider Owner
Action: Allow
```

**Include** (Who can access):

**Option A: Your Email** (simplest)
```
Email → Enter → your-email@example.com
```

**Option B: Your GitHub** (alternative)
```
GitHub → Enter → your-github-username
```

**Option C: Both** (recommended)
```
Email → your-email@example.com
OR
GitHub → your-github-username
```

Click: **"Save policy"**

---

## Step 6: Test It Works! (30 seconds)

### Test 1: Provider Should Require Auth

Open browser: https://provider.reverb256.ca

**Expected**: Should see login page (Email or GitHub)

**Success!** ✅

### Test 2: Login With Your Email

1. Click: **"Email a one-time PIN"**
2. Enter: your-email@example.com
3. Check email → Enter 6-digit PIN
4. **Access granted!** ✅

### Test 3: Verify Tenant Endpoints Are Public

Open browser: https://test.ingress.reverb256.ca

**Expected**: Should work directly (no login)

**Success!** ✅

---

## Step 7: Deploy Your Config (1 minute)

Your NixOS config is already updated! Just deploy:

```bash
# Deploy configuration
nixos-rebuild test --fast

# Restart cloudflared
systemctl restart cloudflared-tunnel

# Check status
systemctl status cloudflared-tunnel
```

---

## ✅ Verification Checklist

- [ ] Can access provider with email auth
- [ ] Can access provider with GitHub auth
- [ ] Tenant endpoints work without auth
- [ ] Configuration deployed
- [ ] Cloudflared restarted successfully

---

## 🎯 You're Done!

**What changed**:
- ✅ Provider endpoints require authentication
- ✅ Tenant endpoints remain public
- ✅ Professional security for your Akash provider

**Time spent**: 3 minutes
**Security level**: HIGH 🔒

---

## 🆘 Quick Troubleshooting

**"Access Denied" error**:
- Check you're using the correct email/GitHub username
- Make sure policy is set to "Allow" (not "Deny")

**"Tenant endpoints require auth"**:
- Check cloudflared config (should have NO `accessPolicy` for `*.ingress`)
- Restart cloudflared: `systemctl restart cloudflared-tunnel`

**"Magic link not received"**:
- Check spam folder
- Try GitHub auth instead

---

## 📚 Full Documentation

**Detailed guide**: `/etc/nixos/docs/cloudflare/CLOUDFLARE_ZERO_TRUST_SETUP.md`
**Quick reference**: `/etc/nixos/docs/cloudflare/ZERO_TRUST_QUICKSTART.md`

---

**Questions?**
- Cloudflare docs: https://developers.cloudflare.com/cloudflare-one/
- Akash provider docs: https://docs.akash.network/providers
