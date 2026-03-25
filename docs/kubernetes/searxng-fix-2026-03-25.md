# SearXNG Search Timeout Fix - 2026-03-25

## Problem
SearXNG was returning 0 search results with all engines timing out after 3 seconds.

## Root Cause
The default HTTP client timeout in SearXNG is **3.0 seconds**, which is too short for search engines to respond through Kubernetes networking (additional latency vs direct internet connection).

## Solution
Updated SearXNG configuration with increased timeouts:

### ConfigMap Changes (`searxng-configmap.yaml`)
```yaml
search:
  max_request_timeout: 14.0  # Global timeout for all search requests

client:
  timeout: 12.0  # Total timeout for HTTP requests
  connect_timeout: 5.0  # Time to establish connection
  read_timeout: 8.0  # Time to read response

engines:
  - name: duckduckgo
    timeout: 10.0  # Engine-specific timeout
  - name: brave
    timeout: 10.0
  # ... etc
```

## Results

### Before Fix
- Search results: **0**
- All engines: **timeout** (3.0s limit)
- Error: `HTTP requests timeout (search duration: 3.6s, timeout: 3.0s)`

### After Fix
- Search results: **55** ✅
- Working engines: Brave, Wikipedia, Startpage, StackOverflow, GitHub
- Search time: **3.1s** (within 12s timeout)
- DuckDuckGo: CAPTCHA (expected from pod IP)

## End-to-End Testing

### 1. Kubernetes Service
```bash
kubectl get pods -n search -l app=searxng
# 3/3 pods running ✅
```

### 2. HTTPS Access (Browser)
```bash
curl https://search.reverb256.ca/search?q=test
# 55 results ✅
# No certificate warnings ✅
```

### 3. MCP Integration
```python
# Knowledge Fabric can now query SearXNG
SEARXNG_URL = "https://search.reverb256.ca"
# Returns 48 results for "nixos" query ✅
```

## Configuration Files

### Updated Files
- `/etc/nixos/kubernetes-manifests/search/searxng-configmap.yaml` - Working ConfigMap
- `/etc/nixos/kubernetes-manifests/search/searxng-deployment.yaml` - Deployment manifest

### NixOS Integration
- `/etc/nixos/modules/services/ai-inference/default.nix` - MCP server configuration
  - `SEARXNG_URL = "https://search.reverb256.ca"`
  - `SEARXNG_CACHE_TTL = "300"`

### Certificate Trust
- `/etc/nixos/modules/security/caddy-ca.nix` - Caddy CA trust module
- `/etc/nixos/certs/caddy-root-ca.crt` - CA certificate
- Enabled on all cluster hosts (zephyr, nexus, forge, sentry)

## Access Methods

### Browser
- **URL**: https://search.reverb256.ca
- **Certificate**: Trusted (no warnings)
- **Features**: HTML UI, JSON API

### MCP (Knowledge Fabric)
- **URL**: https://search.reverb256.ca
- **Format**: JSON (`/search?q=...&format=json`)
- **Cache**: 5-minute TTL

### Kubernetes Internal
- **Service**: searxng.search.svc.cluster.local:8080
- **ClusterIP**: 10.0.0.100:8080
- **Health Check**: http://10.0.0.100:8080/healthz

## Known Issues

### DuckDuckGo CAPTCHA
- **Issue**: DuckDuckGo returns CAPTCHA (wt-wt)
- **Cause**: Bot detection from Kubernetes pod IP
- **Impact**: DuckDuckGo engine inactive
- **Workaround**: Other engines (Brave, Wikipedia) work fine
- **Future**: Consider rotating proxy IPs or user-agent rotation

### Engine Timeout Logging
Old pods may still show timeout errors in logs. Check new pod logs:
```bash
kubectl logs -n search searxng-<new-pod> --tail=50
```

## Verification Commands

```bash
# Check pod status
kubectl get pods -n search -l app=searxng

# Test search from pod
kubectl exec -n search searxng-<pod> -- python3 -c "
import urllib.request, json
r = urllib.request.urlopen('http://127.0.0.1:8080/search?q=test&format=json')
print(json.load(r)['number_of_results'])
"

# Test HTTPS access
curl -s "https://search.reverb256.ca/search?q=test&format=json" | jq '.results | length'

# Test MCP integration
python3 -c "
import os, json, urllib.request, ssl
ctx = ssl.create_default_context()
ctx.load_verify_locations('/etc/static/ssl/certs/ca-certificates.crt')
os.environ['SEARXNG_URL'] = 'https://search.reverb256.ca'
r = urllib.request.urlopen('https://search.reverb256.ca/search?q=nixos&format=json', context=ctx)
print(f'Results: {len(json.load(r)[\"results\"])}')
"
```

## Summary
✅ SearXNG is fully operational with:
- HTTPS access through Caddy ingress
- Certificate trust on all cluster nodes
- Working search results (55 results for "test")
- MCP integration for Knowledge Fabric
- Increased timeouts (12s) for Kubernetes networking

**Status**: PRODUCTION READY ✅
