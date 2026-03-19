# Cloudflare Zero Trust - Quick Start

**5-minute setup guide for securing your Akash provider**

---

## 🚀 Quick Setup (5 minutes)

### 1. Cloudflare Dashboard (2 minutes)

```
1. Go to: https://dash.cloudflare.com
2. Zero Trust → Access → Applications
3. Click: "Add an application"
```

### 2. Application Settings (1 minute)

```
Name: Akash Provider - Reverb256
Auth: Email + GitHub
Session: 24h
```

### 3. Access Policy (1 minute)

```
Policy: Provider Owner
Action: Allow
Email: your-email@example.com
```

### 4. Add URLs (1 minute)

```
https://provider.reverb256.ca
https://grpc.provider.reverb256.ca
```

### 5. Deploy (1 minute)

```bash
# Deploy your updated configuration
nixos-rebuild test --fast

# Restart cloudflared
systemctl restart cloudflared-tunnel
```

---

## ✅ Test It Works

### Test Provider (Should Require Login)

```bash
curl -I https://provider.reverb256.ca
# Should return: 403 Forbidden (redirects to login)
```

### Test Tenant (Should Work Directly)

```bash
curl -I https://test.ingress.reverb256.ca
# Should return: 200 OK (no login required)
```

---

## 📋 Checklist

- [ ] Zero Trust application created
- [ ] Email auth enabled
- [ ] GitHub auth enabled
- [ ] Your email added to policy
- [ ] Provider URLs added
- [ ] NixOS config deployed
- [ ] Cloudflared restarted
- [ ] Provider requires auth (✅)
- [ ] Tenant endpoints public (✅)

---

## 🆘 Troubleshooting

**Problem**: Can't access provider at all
```bash
# Check cloudflared status
systemctl status cloudflared-tunnel

# Check logs
journalctl -u cloudflared-tunnel -n 50
```

**Problem**: Tenant endpoints require auth
```bash
# Check config has NO accessPolicy for tenant endpoints
grep -A5 "ingress.reverb256.ca" /etc/nixos/hosts/zephyr/configuration.nix
```

**Problem**: Magic link not received
```bash
# Check spam folder
# Try alternative: GitHub auth
```

---

## 📞 Need Help?

**Full Guide**: `/etc/nixos/docs/cloudflare/CLOUDFLARE_ZERO_TRUST_SETUP.md`
**Cloudflare Docs**: https://developers.cloudflare.com/cloudflare-one/

---

**Done in 5 minutes!** 🎉
