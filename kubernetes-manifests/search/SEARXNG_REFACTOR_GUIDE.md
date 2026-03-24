# SearXNG Refactoring Guide

**Date:** 2026-03-22
**Status:** Ready for Deployment
**Impact:** Fixes HTTP 403 bot detection errors, improves search reliability

---

## Problem Summary

**Original Issues:**
- HTTP 403 errors from external search engines (Google, Bing, DuckDuckGo)
- Bot detection blocking SearXNG automated queries
- MCP search tools failing with "Cannot connect to SearXNG service"

**Root Cause:**
- Minimal configuration with no User-Agent rotation
- No rate limiting per engine
- Missing timeout configurations
- Aggressive engines (Google, Bing) without proper headers

---

## Refactored Configuration

### Key Improvements

**1. Outgoing Request Configuration**
```yaml
outgoing:
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  request_timeout: 15.0
  max_request_timeout: 30.0
  reconnect_time: 5
  pool_connections: 100
  enable_http2: true
```

**2. Engine Selection Strategy**
- ✅ **Keep:** Wikipedia, ArXiv, GitHub, StackOverflow, NixOS Wiki (bot-friendly)
- ✅ **Keep:** DuckDuckGo, Brave (privacy-focused, more lenient)
- ❌ **Remove:** Google, Bing, StartPage (too aggressive with bot detection)

**3. Resource Allocation**
- Increased CPU limits: 500m → 1000m
- Increased memory limits: 512Mi → 1Gi
- Better probe timeouts for slower engines

**4. Health Checks**
- Liveness probe: 30s initial delay, 5s timeout
- Readiness probe: 10s initial delay, 5s timeout
- Failure threshold: 3 (allows temporary engine failures)

---

## Deployment Steps

### Step 1: Deploy Refactored Configuration

```bash
# Deploy the refactored manifest
kubectl apply -f kubernetes-manifests/search/searxng-deployment-refactored.yaml

# Wait for pods to be ready
kubectl rollout status deployment/searxng-refactored -n search
```

### Step 2: Verify Deployment

```bash
# Check pod status
kubectl get pods -n search -l app=searxng-refactored

# Check logs for errors
kubectl logs -n search deployment/searxng-refactored --tail=50

# Test service connectivity
kubectl run test-pod --image=curlimages/curl -i --rm --restart=Never \
  -- curl -s http://searxng-refactored.search.svc.cluster.local:8080/healthz
```

### Step 3: Test Search Functionality

```bash
# Test Wikipedia search
curl -s 'http://10.0.0.247:8080/search?format=json&engines=wiki&q=nixos' | jq -r '.[0].title'

# Test GitHub search
curl -s 'http://10.0.0.247:8080/search?format=json&engines=github&q=kubernetes' | jq -r '.[0].title'

# Test StackOverflow search
curl -s 'http://10.0.0.247:8080/search?format=json&engines=stackoverflow&q=nixos' | jq -r '.[0].title'
```

### Step 4: Update MCP Configuration

```bash
# Update .mcp.json to use new service
sed -i 's/"SEARXNG_URL": "http:\/\/10.0.0.247:8080"/"SEARXNG_URL": "http:\/\/10.0.0.247:8080"/' .mcp.json

# Or use DNS name (recommended)
sed -i 's/"SEARXNG_URL": "http:\/\/10.0.0.247:8080"/"SEARXNG_URL": "http:\/\/searxng-refactored.search.svc.cluster.local:8080"/' .mcp.json

# Restart MCP gateway (if running as service)
pkill -f mcp-gateway-bridge
```

### Step 5: Test MCP Integration

```bash
# Test search_code tool
# (This will be done via Claude Code MCP tools)
```

---

## Rollback Plan

If issues occur, rollback to original configuration:

```bash
# Delete refactored deployment
kubectl delete -f kubernetes-manifests/search/searxng-deployment-refactored.yaml

# Original deployment still exists and will handle traffic
kubectl get pods -n search -l app=searxng
```

---

## Monitoring

### Key Metrics to Watch

```bash
# Pod health
kubectl get pods -n search -l app=searxng-refactored

# Search response time
time curl -s 'http://searxng-refactored.search.svc.cluster.local:8080/search?q=test' > /dev/null

# Error rate
kubectl logs -n search deployment/searxng-refactored --tail=100 | grep -i error

# Engine-specific errors
kubectl logs -n search deployment/searxng-refactored --tail=100 | grep -E "(403|429|timeout)"
```

### Expected Behavior

- **Wikipedia, ArXiv:** < 1s response, 0% errors
- **GitHub, StackOverflow:** 1-3s response, < 5% errors
- **DuckDuckGo, Brave:** 2-5s response, < 10% errors
- **No HTTP 403 errors** from enabled engines

---

## Engine Categories

### Academic & Knowledge (High Reliability)
- Wikipedia, Wikidata, ArXiv, PubMed
- **Response Time:** < 1s
- **Error Rate:** < 1%

### Code & Development (Medium Reliability)
- GitHub, StackOverflow, NPM, PyPI, NixOS Wiki
- **Response Time:** 1-3s
- **Error Rate:** < 5%

### Privacy Search (Variable Reliability)
- DuckDuckGo, Brave
- **Response Time:** 2-5s
- **Error Rate:** < 10%

### Blocked (Disabled)
- Google, Bing, StartPage
- **Reason:** Aggressive bot detection, CAPTCHA requirements

---

## Known Limitations

1. **No Google/Bing Results:** These engines block automated queries aggressively
2. **Rate Limiting:** Some engines may still return 429 (Too Many Requests)
3. **Response Time:** Academic engines faster than privacy search engines
4. **Coverage:** Limited to bot-friendly sources (sufficient for code/docs search)

---

## Future Improvements

### Option 1: Tor Network Integration
- Route traffic through Tor for IP rotation
- Pros: Bypasses IP-based blocking
- Cons: Slower, more complex setup

### Option 2: Residential Proxies
- Use paid proxy services (Bright Data, Smartproxy)
- Pros: Higher success rate with blocked engines
- Cons: Cost, maintenance overhead

### Option 3: Custom API Integrations
- Direct API calls to Google Custom Search, Bing Search API
- Pros: Reliable, no bot detection
- Cons: API costs, query limits

### Option 4: Specialized Search Engines
- Add more academic/technical engines (Semantic Scholar, IEEE Xplore)
- Pros: Better for technical queries
- Cons: Narrower coverage

---

## Success Criteria

Deployment is successful when:

- ✅ All 3 pods Running and Ready
- ✅ Zero HTTP 403 errors in logs
- ✅ Search queries return JSON results
- ✅ MCP `search_code` tool works
- ✅ Response time < 5s for 90% of queries
- ✅ No pod restarts in first 30 minutes

---

## Maintenance

### Regular Tasks

**Weekly:**
- Check logs for new engine errors
- Monitor response times
- Review engine availability

**Monthly:**
- Update SearXNG image (security patches)
- Review and rotate engine list
- Test MCP integration

**Quarterly:**
- Performance benchmarking
- Engine reliability analysis
- Cost/benefit of proxy services

---

**Documentation Version:** 1.0
**Last Updated:** 2026-03-22
**Next Review:** After 1 week of operation
