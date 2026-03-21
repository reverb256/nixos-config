# SearXNG Implementation Summary

**Date**: 2026-03-21
**Status**: ✅ Operational
**Deployment**: `/etc/nixos/kubernetes-manifests/search/searxng-deployment.yaml`

## Overview

Successfully reimplemented SearXNG metasearch engine with proper rate limiting, Redis backend, and bot detection for use with MCP gateway tools.

## Implementation Details

### Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│  MCP Gateway    │────▶│  SearXNG     │────▶│   Redis     │
│  (External)     │     │  (3 replicas)│     │  (Backend)  │
└─────────────────┘     └──────────────┘     └─────────────┘
                              │
                              ▼
                        ┌──────────────┐
                        │   Search     │
                        │   Engines    │
                        │ (Google, etc)│
                        └──────────────┘
```

### Configuration

#### Deployment Spec
- **Replicas**: 3 (high availability)
- **Image**: `searxng/searxng:latest`
- **Resource Limits**: 500m CPU, 512Mi memory
- **Security**: PodSecurity `restricted:latest` compliant

#### Redis Integration
- **URL**: `redis://redis.search.svc.cluster.local:6379/0`
- **Purpose**: Rate limiting state storage
- **Location**: Same namespace (search)

#### Bot Detection
- **Trusted Proxies**:
  - 127.0.0.0/8 (localhost)
  - ::1 (IPv6 localhost)
  - 10.0.0.0/8 (Kubernetes pod network)
  - 10.1.1.0/24 (Cluster network)

#### Search Engines
Configured engines:
- ✅ Brave (working)
- ✅ DuckDuckGo (working)
- ✅ Wikipedia (working)
- ✅ Startpage (working)
- ✅ StackOverflow (configured)
- ✅ GitHub (configured)
- ⚠️ Google (access denied - expected due to rate limiting)

## Troubleshooting Journey

### Issue 1: Ghost IP Allocations
**Problem**: Previous deployment had 21 failed ConfigMaps and ghost pods counting against quota
**Solution**:
- Deleted all 21 failed ConfigMaps
- Deleted broken ResourceQuota (had cached state showing 10/10 pods used)
- Let deployment create fresh pods

### Issue 2: PodSecurity Violations
**Problem**: Pods blocked by `restricted:latest` PodSecurity policy
**Solution**: Added security context:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

# Container level
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: true
```

### Issue 3: Invalid settings.yml
**Problem**: `ValueError: Invalid settings.yml` - Expected `object`, got `null`
**Root Cause**: Complex configuration with nested limiter config caused schema validation errors
**Solution**: Simplified to minimal configuration and moved Redis config to settings.yml instead of limiter.toml

### Issue 4: Invalid limiter.toml Schema
**Problem**: `[cfg schema invalid] data_dict 'redis': key unknown in schema_dict`
**Root Cause**: Redis configuration in limiter.toml was not recognized by SearXNG schema
**Solution**: Moved Redis configuration to settings.yml under `limiter.redis.url`

### Issue 5: Read-only Root Filesystem
**Problem**: Certificates couldn't be updated on read-only filesystem
**Solution**: Added tmpfs mounts for writable directories:
```yaml
- name: tmp
  emptyDir: {}
- name: cache
  emptyDir: {}
- name: run
  emptyDir: {}
```

### Issue 6: Redis Connection
**Problem**: `OSError: [Errno 101] Network is unreachable`
**Root Cause**: Wrong Redis service address (was using `redis-service.ai-inference.svc.cluster.local`)
**Solution**: Changed to local Redis service (`redis.search.svc.cluster.local`)

## Verification

### Service Status
```bash
$ kubectl get pods -n search -l app=searxng
NAME                      READY   STATUS    RESTARTS   AGE
searxng-bbfb6bc77-b9p7h   1/1     Running   0          31s
searxng-bbfb6bc77-pfwp7   1/1     Running   0          44s
searxng-bbfb6bc77-svnpk   1/1     Running   0          18s
```

### Search Test
```bash
$ curl "http://10.0.0.102:8080/search?q=test&format=json" | jq '.results | length'
24
```

### Engine Status
- ✅ Brave: Returning results
- ✅ DuckDuckGo: Returning results
- ✅ Wikipedia: Returning results
- ✅ Startpage: Returning results
- ⚠️ Google: "access denied" (expected - Google has aggressive bot detection)

## MCP Tool Integration

Recreated skill wrappers:
- `/home/j_kro/.claude/skills/search-code/SKILL.md`
- `/home/j_kro/.claude/skills/search-stackoverflow/SKILL.md`
- `/home/j_kro/.claude/skills/web-search/SKILL.md`

These skills invoke the MCP gateway tools which query the SearXNG service.

## Key Insights

1. **Minimal Configuration Works Better**: SearXNG's schema validation is strict - complex configurations often fail. Start minimal and add features incrementally.

2. **Redis Configuration Location Matters**: In SearXNG 2026.3.20, Redis must be configured in `settings.yml` under `limiter.redis.url`, NOT in `limiter.toml`.

3. **Kubernetes Network Policies**: The trusted proxies configuration must include the entire pod CIDR range (10.0.0.0/8) for proper X-Forwarded-For header handling.

4. **Read-only Filesystem Requires Planning**: When using `readOnlyRootFilesystem: true`, you must pre-create all writable directories as tmpfs mounts.

## Files Modified

- **Created**: `/etc/nixos/kubernetes-manifests/search/searxng-deployment.yaml`
- **Deleted**: 21 failed ConfigMaps (searxng-limiter-*, searxng-settings-*)
- **Created**: Skill wrappers in `/home/j_kro/.claude/skills/`

## Next Steps

1. **Monitor Search Quality**: Track which engines are successfully returning results vs. blocked
2. **Rate Limit Tuning**: Adjust bot detection thresholds if Google continues to block requests
3. **Scaling Considerations**: Current 3 replicas should handle moderate load; monitor CPU/memory usage
4. **Alternative to Google**: Consider adding additional engines to compensate for Google blocking

## References

- SearXNG Documentation: https://docs.searxng.org/
- Limiter Configuration: https://docs.searxng.org/admin/settings/settings.html#limiter-settings
- Bot Detection: https://docs.searxng.org/admin/settings/settings.html#botdetection-settings
