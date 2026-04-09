# SearXNG Fix Plan

## Problem
All search engines blocking SearXNG with 403/CAPTCHA due to:
1. Single IP (Kubernetes cluster IP)
2. No X-Forwarded headers from Caddy
3. Missing engines (StackOverflow)
4. No proxy rotation

## Solutions

### Option 1: Use Tor Proxy (Recommended for Privacy)
```yaml
# Add to searxng-deployment.yaml
env:
  - name: SEARXNG_PROXY_URL
    value: "socks5h://tor-service:9050"
```

Deploy Tor service alongside SearXNG for IP rotation.

### Option 2: Use Commercial Proxy
- Use residential proxy service (Bright Data, Smartproxy)
- Configure outgoing.proxy in settings.yml

### Option 3: Use Hosted SearXNG Instance
- Don't self-host
- Use public instances: https://searx.space/
- Configure MCP gateway to use external instance

### Option 4: Fix Headers + Rate Limiting (Partial Fix)
1. Configure Caddy to pass X-Forwarded-For headers
2. Fix Redis limiter connection
3. Remove broken engines (StackOverflow, GitHub)
4. Add request throttling

## Quick Fix (Today)
Disable SearXNG, use direct MCP tools:
- ✅ search_nixos_options (works)
- ✅ search_code (uses GitHub API directly)
- ✅ search_research (uses academic APIs)

## Long-term Fix (This Week)
1. Deploy Tor alongside SearXNG
2. Configure SearXNG to use Tor proxy
3. Test search functionality
4. Remove broken engines from config
