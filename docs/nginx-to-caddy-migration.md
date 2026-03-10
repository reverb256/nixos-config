# Nginx to Caddy Migration Guide

## Current Nginx Usage Status

| Service | Priority | Complexity | Note |
|---------|----------|------------|------|
| Prometheus | Low | Low | Comment mentions nginx, not actively used |
| SearXNG | Low | Low | Comment suggests nginx/caddy option |
| Nextcloud | Medium | High | Full nginx reverse proxy with SSL |
| Tailscale Auth | Medium | Medium | Authentication integration |

## Migration Strategy

### Phase 1: Simple Services (Start Here)

#### SearXNG (Low hanging fruit)
Current: Comment mentions nginx/caddy
Migration: Add Caddy reverse proxy configuration
```nix
# In hosts/zephyr/configuration.nix
services.caddy-module = {
  "search.zephyr.tigris-ule.ts.net" = {
    port = 8080;
    reverseProxy = "127.0.0.1";
    reverseProxyPort = 8888;
  };
};
services.searxng.nginx.enable = false; # Disable nginx
```

#### Prometheus (Local monitoring)
Current: Listens on localhost only
Migration: Add Caddy for external access
```nix
services.caddy-module = {
  "prometheus.zephyr.tigris-ule.ts.net" = {
    port = 9091;
    reverseProxy = "127.0.0.1";
    reverseProxyPort = 9090;
    basicAuth = {
      user = "prometheus";
      password = "$2a$14$..."; # Generate with caddy hash-password
    };
  };
};
```

### Phase 2: Medium Complexity

#### Tailscale Auth (AI Inference)
Current: nginx authentication integration
Migration: Caddy basicauth + reverse proxy
```nix
services.caddy-module = {
  "ai.zephyr.tigris-ule.ts.net" = {
    reverseProxy = "127.0.0.1";
    reverseProxyPort = 8080;
    # Tailscale already handles auth, just proxy through
  };
};
```

### Phase 3: Complex Services (Careful Testing Required)

#### Nextcloud
Current: Full nginx reverse proxy with SSL, security headers, gzip
Migration: Needs careful testing
```nix
# DISABLE nginx first
services.nextcloud.nginx.enable = false;

# ADD Caddy with equivalent features
services.caddy-module = {
  "${config.services.nextcloud.hostName}" = {
    port = 443;
    reverseProxy = "127.0.0.1";
    reverseProxyPort = 8080;
    tls = {
      email = "admin@example.com";
    };
  };
};

# ADD security headers via Caddy (in extra config)
services.caddy.config = ''
  ${config.services.nextcloud.hostName}:443 {
    reverse_proxy 127.0.0.1:8080

    # Security headers (equivalent to nginx)
    header {
      Strict-Transport-Security "max-age=31536000; includeSubDomains"
      X-Frame-Options "SAMEORIGIN"
      X-Content-Type-Options "nosniff"
      X-XSS-Protection "1; mode=block"
    }

    tls {
      dns cloudflare {env.CLOUDFLARE_API_TOKEN}
      resolvers 1.1.1.1
    }
  }
'';
```

## Testing Procedure

1. **Add Caddy config** to host configuration
2. **Disable nginx** for that service: `services.<service>.nginx.enable = false`
3. **Test locally**: `curl http://localhost:8080`
4. **Test externally**: `curl https://your-domain.com`
5. **Monitor logs**: `journalctl -u caddy -f`
6. **Rollback if needed**: Re-enable nginx, remove Caddy config

## Caddy Advantages Realized

✅ **Automatic HTTPS**: No more ACME/Let's Encrypt manual setup
✅ **Simple Config**: 5 lines vs 50+ lines of nginx
✅ **HTTP/3 Support**: Built-in, no extra modules
✅ **Graceful Reloads**: Zero downtime config changes
✅ **Automatic Renewal**: Certs renew without restart

## Common Nginx → Caddy Patterns

| Nginx | Caddy |
|-------|-------|
| `proxy_pass http://backend` | `reverse_proxy backend` |
| `listen 443 ssl` | Automatic with `tls` directive |
| `server_name example.com` | `example.com { }` block |
| `root /var/www` | `root * /var/www` + `file_server` |
| `auth_basic "Realm"` | `basicauth user hash` |
| `add_header` | `header { }` |
| `gzip on` | Automatic |

## Password Hash Generation

```bash
# Generate bcrypt hash for Caddy basic auth
caddy hash-password --plaintext "your-password"
# Output: $2a$14$...
```

## Migration Checklist

- [ ] Phase 1: SearXNG (simple proxy)
- [ ] Phase 1: Prometheus external access
- [ ] Phase 2: Tailscale auth
- [ ] Phase 3: Nextcloud (careful testing!)
- [ ] Remove nginx from system entirely (last step)
