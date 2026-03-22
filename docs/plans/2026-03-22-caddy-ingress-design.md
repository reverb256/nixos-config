# Full-Scale Caddy Ingress Controller Design

**Status:** Design Complete | **Created:** 2026-03-22 | **Owner:** j_kro
**Type:** Infrastructure Enhancement | **Priority:** High
**Related:** Akash Provider, Kubernetes Migration, GPU Marketplace

---

## Executive Summary

Design and implementation of a production-grade, full-spectrum Caddy ingress controller for the 4-node NixOS Kubernetes cluster. Replaces basic Caddy deployment with custom build including 5 modules (security, rate-limiting, caching, compression, IP filtering) for comprehensive edge security, performance, and observability.

**Goals:**
1. Replace basic Caddy with feature-rich ingress controller
2. Add comprehensive security (rate limiting, headers, IP filtering)
3. Implement three-layer caching (response cache, compression, Cloudflare CDN)
4. Enable full observability (metrics, logs, health checks)
5. Maintain zero-downtime deployment with rollback capability

**Timeline:** 5 days (build, test, canary, rollout, cleanup)

---

## Architecture Overview

### Current State

**Basic Caddy Deployment:**
- 2/3 pods running (nexus, sentry)
- Minimal configuration (health check, echo test)
- Most service routes disabled
- No security, caching, or monitoring modules
- Manual configuration management

### Target State

**Full-Scale Caddy Ingress:**
- 2/2 pods running (nexus, sentry)
- All services enabled with full configuration
- 5 modules integrated (security, rate-limit, cache, zip, ipfilter)
- Comprehensive monitoring (Prometheus metrics, Grafana dashboards)
- Automated deployment via GHCR registry

### Traffic Flow

```
External Request
    ↓
Cloudflare Edge (DDoS, WAF, Bot detection)
    ↓
Cloudflare Tunnel (encrypted)
    ↓
Caddy Ingress (rate limit, cache, security headers)
    ↓
Kubernetes Service (CoreDNS resolution)
    ↓
Application Pods (load balanced)
```

---

## Custom Caddy Build

### Build Strategy: NixOS-Based

**Rationale:**
- Reproducible builds (same binary every time)
- Consistent with cluster infrastructure (all NixOS)
- Version control via Git (flake.lock)
- Easy rollback (previous commits)

### Module Selection

| Module | Purpose | Priority |
|--------|---------|----------|
| caddy-security | Security headers (HSTS, CSP, XSS) | P0 (Critical) |
| caddy-rate-limit | API abuse prevention | P0 (Critical) |
| caddy-cache | Response caching | P1 (High) |
| caddy-zip | Compression (gzip, brotli, zstd) | P1 (High) |
| caddy-ipfilter | IP allowlist/blocklist | P2 (Medium) |

### Package Structure

**File: pkgs/caddy-with-modules/default.nix**
```nix
{ lib, buildGoModule, fetchFromGitHub, plugins }:

buildGoModule {
  pname = "caddy-with-modules";
  version = "2.8.0";

  src = fetchFromGitHub {
    owner = "caddyserver";
    repo = "caddy";
    rev = "v${version}";
    hash = "sha256-XXXX";  # To be populated
  };

  vendorHash = "sha256-YYYY";  # To be populated

  buildInputs = plugins;

  postInstall = ''
    mv $out/bin/caddy $out/bin/caddy-with-modules
  '';

  meta = with lib; {
    description = "Caddy web server with custom modules";
    license = licenses.asl20;
  };
}
```

**File: pkgs/caddy-ingress-image/default.nix**
```nix
{ lib, pkgs, caddy }:

pkgs.dockerTools.buildLayeredImage {
  name = "caddy-ingress";
  tag = "latest";

  contents = [ caddy pkgs.busybox ];

  config = {
    Cmd = [ "/bin/caddy-with-modules" "run" "--config" "/etc/caddy/Caddyfile" ];
    ExposedPorts = { "80" = {}; "443" = {}; "2019" = {}; };
    Volumes = {
      "/etc/caddy" = {};
      "/data" = {};
      "/var/log/caddy" = {};
      "/tmp/caddy-rate-limit" = {};
    };
  };

  reproducible = true;
}
```

### Registry Strategy

**Primary: GitHub Container Registry (ghcr.io)**
- Unlimited public packages
- High bandwidth (no rate limits)
- GitHub integration (CI/CD)
- Image: `ghcr.io/j_kro/caddy-ingress:v2.8.0`

**Backup: Docker Hub (docker.io)**
- Rate limited (100 pulls/6hrs free tier)
- Fallback option
- Image: `docker.io/jkro/caddy-ingress:v2.8.0`

---

## TLS Certificate Management

### Hybrid TLS Architecture

**Public Services** (provider.reverb256.ca):
- Cloudflare API DNS challenge
- No port 80 exposure required
- Token: `/run/agenix/cloudflare-api-token` (already exists)
- Automated renewal via Caddy

**Internal Services** (*.cluster.local):
- Internal CA for service mesh
- No external certificate authority
- Instant issuance (no rate limits)
- Valid for entire cluster

### Implementation Details

**Public service (Akash provider):**
```caddyfile
provider.reverb256.ca {
    reverse_proxy akash-provider:8443

    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        resolvers 1.1.1.1
    }

    header {
        Strict-Transport-Security "max-age=31536000"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
    }
}
```

**Internal service (AI inference):**
```caddyfile
ai-inference.cluster.local {
    reverse_proxy ai-inference-service:8000

    tls internal

    cache {
        ttl 3600
        key_scheme { query header Authorization }
    }
}
```

### Certificate Automation

- **Cloudflare certificates**: Automatic via Caddy (14-day renewal window)
- **Internal certificates**: 90-day validity, auto-renew at 60 days
- **Monitoring**: Prometheus metrics on certificate expiry
- **Alerting**: 30-day warning before expiry

---

## Caching Strategy

### Three-Layer Architecture

**Layer 1: Response Cache (Caddy)**
- In-memory cache for API responses
- Per-route TTL configuration
- Cache key customization (query params, headers)
- Best for: AI inference, search results, API calls

**Layer 2: Static Asset Compression (caddy-zip)**
- Zstandard (best compression, level 3)
- Brotli (good for web, quality 4)
- Gzip (legacy compatibility, level 5)
- Best for: JavaScript, CSS, HTML, JSON, SVG

**Layer 3: Cloudflare CDN (edge cache)**
- Global edge network (300+ data centers)
- Automatic cache purging via API
- Browser cache TTL control
- Best for: Static assets, public API responses

### Cache Configuration Examples

**AI inference (1 hour TTL):**
```caddyfile
ai-inference.cluster.local {
    reverse_proxy ai-inference-service:8000

    cache {
        ttl 3600
        key_scheme {
            query
            header Authorization  # User-specific cache
        }
        status 200
    }

    header Cache-Control "public, max-age=3600"
}
```

**SearXNG (5 minute TTL):**
```caddyfile
searxng.cluster.local {
    reverse_proxy searxng-service:8080

    cache {
        ttl 300
        key_scheme { query form q categories }
        status 200
    }
}
```

### Performance Benchmarks

**Expected cache hit rates:**
- AI inference: 60-80% (repetitive queries)
- Search results: 40-60% (popular queries)
- Static assets: 95-99% (JS/CSS)

**Bandwidth savings:**
- Zstd compression: 70-80% reduction
- Brotli compression: 65-75% reduction
- Gzip compression: 60-70% reduction

---

## Security Implementation

### Defense-in-Depth Stack

**Layer 1: Network Security (Cloudflare)**
- DDoS protection (layer 3/4)
- Bot detection and mitigation
- IP reputation filtering
- **Already provided** by Cloudflare Tunnel

**Layer 2: Application Security (Caddy modules)**
- Rate limiting (caddy-rate-limit)
- Security headers (caddy-security)
- IP filtering (caddy-ipfilter)
- **New implementation** with full-scale Caddy

### Rate Limiting Configuration

**AI inference (strict - GPU compute expensive):**
```caddyfile
ai-inference.cluster.local {
    @ai_limit {
        rate_limit {
            zone ai_inference {
                store file_system /tmp/caddy-rate-limit
                rate 10 1m
                burst 5
            }
            key {remote_host}
        }
    }

    handle @ai_limit {
        respond "Rate limit exceeded" 429
    }
}
```

**SearXNG (moderate - search costs):**
```caddyfile
searxng.cluster.local {
    @search_limit {
        rate_limit {
            zone search {
                rate 30 1m
                burst 10
            }
            key {remote_host}
        }
    }
}
```

### Security Headers

**Global headers (all routes):**
```caddyfile
{
    security {
        header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        header X-Content-Type-Options "nosniff"
        header X-Frame-Options "DENY"
        header Referrer-Policy "strict-origin-when-cross-origin"
        header Content-Security-Policy "default-src 'self'"
    }
}
```

**Per-route overrides:**
```caddyfile
# Home Assistant (relaxed CSP for UI)
home-assistant.cluster.local {
    header {
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'"
        X-Frame-Options "SAMEORIGIN"
    }
}
```

### IP Filtering

**Internal services (cluster network only):**
```caddyfile
grafana.cluster.local {
    ipfilter {
        allow 10.1.1.0/24     # Cluster network
        allow 100.64.0.0/10   # Tailscale
        block
    }
}
```

---

## Service Routing Configuration

### Service Discovery Integration

**Kubernetes CoreDNS resolution:**
```
Service: ai-inference-service
Namespace: ai-inference
FQDN: ai-inference-service.ai-inference.svc.cluster.local
Route: ai-inference.cluster.local
```

### Route Examples

**AI inference (with load balancing):**
```caddyfile
ai-inference.cluster.local {
    reverse_proxy ai-inference-service.ai-inference:8000 {
        health_uri /health
        health_interval 10s
        health_timeout 5s
        lb_policy least_connection  # Better for variable request duration

        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Cluster-Client "caddy-ingress"
    }

    tls internal
}
```

**WebSocket services (n8n, Home Assistant):**
```caddyfile
n8n.cluster.local {
    reverse_proxy n8n-service.ai-inference:5678 {
        header_up Connection {>Connection}
        header_up Upgrade {>Upgrade}

        transport http {
            read_timeout 0s  # Long-lived connections
            write_timeout 0s
        }
    }

    tls internal
}
```

### Health Check Configuration

**Active health checks (probing):**
```caddyfile
reverse_proxy service:8000 {
    health_uri /health
    health_interval 10s
    health_timeout 5s
    health_status 200

    unhealthy_threshold 3
    healthy_threshold 2
}
```

---

## Monitoring & Observability

### Metrics Pipeline

**Collection flow:**
```
Caddy Ingress (DaemonSet)
    ↓
:2019/metrics endpoint (Prometheus format)
    ↓
Prometheus scraping (15s interval)
    ↓
Grafana dashboards (visualization)
```

### Key Metrics

**Request metrics:**
- `caddy_http_requests_total` (by route, method, status)
- `caddy_http_request_duration_seconds` (histogram)

**Cache metrics:**
- `caddy_cache_hits_total` / `caddy_cache_misses_total`
- `caddy_cache_size_bytes`

**Security metrics:**
- `caddy_rate_limit_requests_blocked_total`
- `caddy_ipfilter_requests_blocked_total`

**Compression metrics:**
- `caddy_compress_zstd_bytes_in_total` / `out_total`
- Compression ratio: `(1 - out/in) * 100`

### Grafana Dashboard Queries

**Cache hit rate:**
```promql
rate(caddy_cache_hits_total[5m]) / (rate(caddy_cache_hits_total[5m]) + rate(caddy_cache_misses_total[5m]))
```

**P95 latency:**
```promql
histogram_quantile(0.95, sum(rate(caddy_http_request_duration_seconds_bucket[5m])) by (route, le))
```

**Bandwidth saved (compression):**
```promql
sum(rate(caddy_compress_zstd_bytes_in_total[5m])) - sum(rate(caddy_compress_zstd_bytes_out_total[5m]))
```

### Alerting Rules

**High error rate (> 5%):**
```yaml
- alert: CaddyHighErrorRate
  expr: rate(caddy_http_requests_total{status=~"5.."}[5m]) / rate(caddy_http_requests_total[5m]) > 0.05
  for: 5m
```

**Low cache hit rate (< 30%):**
```yaml
- alert: CaddyLowCacheHitRate
  expr: rate(caddy_cache_hits_total[5m]) / (rate(caddy_cache_hits_total[5m]) + rate(caddy_cache_misses_total[5m])) < 0.3
  for: 15m
```

---

## Deployment Strategy

### Phased Rollout

**Phase 1: Build & Test** (Day 1-2)
- Build custom Caddy with modules
- Run in test environment
- Validate all modules load correctly

**Phase 2: Canary Deployment** (Day 3)
- Deploy to 1 node (Nexus)
- Monitor metrics and logs
- Validate TLS, caching, security

**Phase 3: Cluster Rollout** (Day 4)
- Deploy to 2nd node (Sentry)
- Validate multi-node operation
- Remove old Caddy pods

**Phase 4: Cleanup & Documentation** (Day 5)
- Update documentation
- Archive old manifests
- Create runbooks

### Build & Push Commands

```bash
# On Zephyr
cd /etc/nixos

# Build the image
nix-build .#packages.x86_64-linux.caddy-ingress-image

# Load into Docker
docker load < result

# Tag for GHCR
docker tag caddy-ingress:latest ghcr.io/j_kro/caddy-ingress:v2.8.0

# Push to GHCR
docker push ghcr.io/j_kro/caddy-ingress:v2.8.0
```

### Canary Deployment

```bash
# Deploy to Nexus only
kubectl patch daemonset caddy-ingress -n ingress-system \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"nexus"}}}}}'

# Rollout restart
kubectl rollout restart daemonset/caddy-ingress -n ingress-system

# Validate
kubectl wait --for=condition=ready pod -l app=caddy-ingress -n ingress-system
curl http://nexus:2019/health
curl -k https://grafana.cluster.local
```

### Validation Checklist

**Basic Functionality:**
- [ ] Pods running on Nexus and Sentry
- [ ] Health endpoints responding
- [ ] Admin API accessible
- [ ] Metrics being collected

**TLS Termination:**
- [ ] Internal services using `.cluster.local` certificates
- [ ] Public service using Cloudflare DNS challenge
- [ ] No certificate errors

**Caching:**
- [ ] Cache hit rate > 50% for ai-inference
- [ ] Compression working (check response headers)

**Security:**
- [ ] Rate limiting blocking excessive requests
- [ ] Security headers present
- [ ] IP filtering working

**Service Routing:**
- [ ] All services accessible via `service.cluster.local`
- [ ] WebSockets working
- [ ] Load balancing distributing requests

### Rollback Procedure

**Immediate rollback:**
```bash
kubectl rollout undo daemonset caddy-ingress -n ingress-system
```

**Full rollback to original Caddy:**
```bash
kubectl scale daemonset caddy-ingress -n ingress-system --replicas=0
kubectl delete daemonset caddy-ingress -n ingress-system
git show HEAD~1:kubernetes-manifests/ingress/03-daemonset.yaml | kubectl apply -f -
```

---

## Success Criteria

### Quantitative Metrics

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| Features | 0 modules | 5 modules | 5/5 |
| Cache hit rate | 0% | > 50% | 60%+ |
| Bandwidth (compression) | 0% | > 70% | 70%+ |
| Security layers | 1 (Cloudflare) | 2 (Cloudflare + Caddy) | 2/2 |
| Observability | Basic | Comprehensive | Metrics + Logs + Traces |

### Qualitative Metrics

- **Operational efficiency**: Automated certificate renewal, centralized config
- **Security posture**: Rate limiting prevents abuse, headers protect users
- **Performance**: Caching reduces backend load, compression saves bandwidth
- **Developer experience**: All services use consistent routing pattern

---

## Risks and Mitigations

### Risk 1: Build failures (NixOS compilation)

**Impact**: Medium
**Mitigation**:
- Use stable NixOS channel
- Pin dependency versions with flake.lock
- Keep previous working build tagged

### Risk 2: Module incompatibility

**Impact**: High
**Mitigation**:
- Test each module individually before integration
- Start with minimal set (security, zip)
- Add modules incrementally

### Risk 3: Canary deployment fails

**Impact**: Medium
**Mitigation**:
- Deploy to single node first
- Comprehensive validation before rollout
- Quick rollback procedure documented

### Risk 4: Performance regression

**Impact**: Medium
**Mitigation**:
- Benchmark before/after
- Monitor response times (p95 latency)
- Tune cache size and rate limits

---

## Open Questions

1. **CI/CD automation**: Should we set up GitHub Actions for automated builds on commit?
   - **Decision**: Optional for now, manual builds give more control

2. **Internal CA implementation**: Should we use cert-manager or manual OpenSSL?
   - **Decision**: Manual OpenSSL for simplicity, can migrate to cert-manager later

3. **Multi-region support**: Should Caddy handle multi-cluster routing?
   - **Decision**: Out of scope, single cluster for now

---

## Related Documentation

**Internal:**
- `modules/services/caddy-ingress.nix` - NixOS module definition
- `kubernetes-manifests/ingress/` - Kubernetes manifests
- `docs/caddy-ingress.md` - Operational guide (to be created)

**External:**
- Caddy Modules: https://caddyserver.com/docs/modules/
- Caddy Security: https://github.com/caddyserver/caddy-security
- Cloudflare API: https://developers.cloudflare.com/api/

---

**Next Steps:**
1. Create implementation plan (detailed step-by-step)
2. Build custom Caddy image
3. Deploy canary to Nexus
4. Validate and rollout to cluster
5. Update documentation and runbooks

---

**Document Status:** Complete | **Version:** 1.0 | **Last Updated:** 2026-03-22
