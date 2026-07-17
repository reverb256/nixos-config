# Cloudflare Zero Trust Integration

**Status**: ✅ Configured | **Updated**: 2026-03-19

---

## Overview

Cloudflare Zero Trust (formerly Cloudflare Access) provides secure access to internal services without VPN. This cluster uses Cloudflare Tunnel to expose services publicly with authentication.

### What's Exposed

| Service | URL | Authentication |
|---------|-----|----------------|
| **AI Inference Gateway** | gateway.example.com | Cloudflare Access |
| **SearXNG** | search.example.com | Public (optional) |
| **Prometheus** | metrics.example.com | Cloudflare Access |
| **Grafana** | dashboards.example.com | Cloudflare Access |

---

## Quick Start

### Initial Setup (One-Time)

```bash
# 1. Install cloudflared
nix-shell -p cloudflared

# 2. Authenticate
cloudflared tunnel login

# 3. Create tunnel
cloudflared tunnel create homelab

# 4. Note the tunnel ID from output
TUNNEL_ID="<your-tunnel-id>"
```

### Configure NixOS Module

Add to `/etc/nixos/modules/services/cloudflared.nix`:

```nix
services.cloudflared = {
  enable = true;
  tunnels = {
    "<TUNNEL_ID>" = {
      credentialsFile = config.age.secrets.cloudflared-token.path;
      default = "http://localhost:8080";
    };
  };
};
```

### Deploy

```bash
# Add tunnel token to agenix
agenix -e cloudflared-token.age

# Deploy to all nodes
just deploy
```

---

## Tunnel Configuration

### Route Individual Services

```yaml
# In ~/.cloudflared/config.yml
ingress:
  # AI Gateway
  - hostname: gateway.example.com
    service: http://localhost:8080
  # SearXNG
  - hostname: search.example.com
    service: http://localhost:8888
  # Prometheus
  - hostname: metrics.example.com
    service: http://localhost:9090
  # Grafana
  - hostname: dashboards.example.com
    service: http://localhost:3001
  # Catch-all
  - service: http_status:404
```

---

## Cloudflare Access Policy

### Create Policy (One-Time)

1. Go to Cloudflare Zero Trust Dashboard
2. Navigate to: **Access → Applications**
3. Click **Add an application**
4. Configure:
   - **Session Duration**: 24h
   - **Gateway Authentication**: Email PIN or OTP
   - **Allowed Emails**: Add your email
5. Save

### Test Access

```bash
# Test tunnel is running
curl http://localhost:8080/health

# Test public access (should redirect to login)
curl https://gateway.example.com/health
```

---

## API Token Permissions

Required token permissions:

| Permission | Purpose |
|------------|---------|
| **Account** > **Cloudflare Tunnel** > **Edit** | Create/manage tunnels |
| **Zone** > **DNS** > **Edit** | Add CNAME records |
| **Account** > **Access** > **Edit** | Configure access policies |

**Token Scopes**:
- Account: All accounts (or specific account)
- Zone: Specific zones (gateway, search, metrics, dashboards)

---

## Troubleshooting

### Tunnel Not Connecting

```bash
# Check cloudflared status
systemctl status cloudflared

# Check logs
journalctl -u cloudflared -f

# Verify credentials
cat /run/cloudflared-token.age
```

### DNS Not Resolving

```bash
# Check CNAME record
dig gateway.example.com CNAME

# Should return: gateway.example.com. → <tunnel-id>.cfargotunnel.com
```

### Access Policy Not Working

1. Verify policy is enabled in Cloudflare dashboard
2. Check email is in allowed list
3. Clear browser cookies and retry
4. Test incognito mode

---

## References

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Access Documentation](https://developers.cloudflare.com/cloudflare-one/policies/access/)
- [cloudflared GitHub](https://github.com/cloudflare/cloudflared)

---

## History

- **2026-03-19**: Consolidated from 7 separate documents
- **2026-03-10**: Initial Cloudflare Tunnel deployment
