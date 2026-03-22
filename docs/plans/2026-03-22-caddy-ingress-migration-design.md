# Caddy Ingress Migration Design

**Date**: 2026-03-22
**Author**: Claude AI Operations
**Status**: Design Complete - Pending Implementation

---

## Executive Summary

Migrate from nginx-ingress to Caddy ingress controller for automatic HTTPS with Let's Encrypt. This migration will replace the existing nginx-ingress deployment with caddy-ingress, maintaining all existing functionality while adding automatic certificate management.

**Scope**: Full migration of all 4 ingress resources to Caddy
**Approach**: Parallel deployment with gradual IngressClass migration
**Timeline**: 5-7 days total

---

## Architecture

### Current State (nginx-ingress)

```
External Client → DNS → LoadBalancer → nginx-ingress-controller → Backend Services
                                                    ↓
                                            Ingress resources (4)
                                            - mlflow-ingress (ai-inference)
                                            - akash-hostname-operator (akash-services)
                                            - akash-provider-v2-letsencrypt-challenge (akash-services)
                                            - searxng (search)
```

**Components**:
- nginx-ingress-controller Deployment (1 replica)
- nginx ingress Class (default)
- TLS: Manual certificate management via Cloudflare

### Target State (caddy-ingress)

```
External Client → DNS → LoadBalancer → caddy-ingress-controller → Backend Services
                                                    ↓
                                            Ingress resources (4)
                                            Automatic Let's Encrypt HTTPS
                                            Certificate auto-renewal
```

**Components**:
- caddy-ingress-controller Deployment (3 replicas, HA)
- Caddy pods (managed by controller)
- Caddy IngressClass (new default)
- TLS: Automatic via Let's Encrypt (HTTP-01 challenge)

---

## Components

### 1. Caddy Ingress Controller

**Repository**: https://github.com/caddyserver/ingress
**Image**: caddy/ingress:latest (or pinned version)

**Responsibilities**:
- Watch Ingress resources
- Generate Caddy configuration from Ingress specs
- Manage Let's Encrypt certificate lifecycle
- Configure Caddy instances via admin API
- Handle certificate renewal

**Configuration**:
```yaml
env:
  - name: CADDY_INGRESS_WATCH_INGRESS_CLASS
    value: "caddy"
  - name: CADDY_INGRESS_EMAIL
    value: "admin@reverb256.ca"  # For Let's Encrypt
  - name: CADDY_INGRESS_LETS_ENCRYPT
    value: "true"
  - name: CADDY_INGRESS_LETS_ENCRYPT_AGREE
    value: "true"
  - name: CADDY_INGRESS_LETS_ENCRYPT_STAGING
    value: "false"  # Set to "true" for testing
```

### 2. Caddy Pods

**Deployment**: 3 replicas (HA across nodes)
**Resources**:
- CPU: 500m (request), 2000m (limit)
- Memory: 512Mi (request), 2Gi (limit)
**Ports**: 80 (HTTP), 443 (HTTPS), 2019 (admin API)

**Storage**:
- Certificate data: EmptyDir (ephemeral)
- Persistent data: PVC for Let's Encrypt account cache

### 3. Certificate Storage

**Type**: Kubernetes Secret `type: kubernetes.io/tls`
**Naming**: `<ingress-name>-tls`
**Structure**:
```
apiVersion: v1
kind: Secret
metadata:
  name: mlflow-ingress-tls
type: kubernetes.io/tls
data:
  tls.crt: <base64 certificate>
  tls.key: <base64 private key>
```

### 4. IngressClass

**Name**: `caddy`
**Controller**: `caddy-ingress-controller/caddy`
**Default**: Yes (after migration)

---

## Data Flow

### Ingress Request Processing

```
1. Client Request → DNS → LoadBalancer (10.1.1.110:80/443)
2. Caddy pod receives request
3. Match SNI hostname to Ingress resource
4. If HTTP: Return 301 redirect to HTTPS
5. If HTTPS: Terminate TLS with Let's Encrypt cert
6. Proxy to backend:
   - Query Kubernetes API for service endpoints
   - Select pod IP (round-robin)
   - Forward request with X-Forwarded-* headers
7. Backend responds → Caddy → Client
```

### Certificate Provisioning Flow

```
1. User creates Ingress resource with hostname
2. caddy-ingress controller detects change via watch
3. Generate Caddy config with TLS automation
4. Caddy requests cert from Let's Encrypt:
   - HTTP-01 challenge: Create temporary HTTP endpoint
   - Prove domain ownership
   - Receive signed certificate
5. Store certificate in Kubernetes Secret
6. Reload Caddy with new certificate
7. Schedule renewal 30 days before expiration
```

### Service Discovery

```
Caddy → Kubernetes API Server
  ↓
Query: GET /api/v1/namespaces/{ns}/services/{svc}
  ↓
Response: Service endpoints (pod IPs)
  ↓
Caddy load balances across pods
```

---

## Error Handling

### Certificate Failures

| Scenario | Handling |
|----------|----------|
| Rate limit exceeded | Backoff exponentially, retry in 1h |
| Challenge fails | Log error, retry after 6h, serve HTTP only |
| Invalid hostname | Skip TLS, log warning, serve HTTP |
| CA unavailable | Use cached cert, retry in 1h |

### Backend Failures

| Scenario | Handling |
|----------|----------|
| Service not found | Return 503, custom error page |
| No ready pods | Health check every 5s, remove from rotation |
| Timeout | Return 504 Gateway Timeout after 30s |
| Connection refused | Mark endpoint unhealthy, try next pod |

### Controller Failures

| Scenario | Handling |
|----------|----------|
| Config generation fails | Log error, keep last known good config |
| Leader election lost | Step down, wait for new leader |
| Crash | Restart by Kubernetes, reload config |

---

## Annotation Migration Guide

### nginx → Caddy Annotations

| nginx Annotation | Caddy Equivalent | Notes |
|------------------|-------------------|-------|
| `nginx.ingress.kubernetes.io/rewrite-target` | `caddy.ingress-controller/rewrite-target` | Direct mapping |
| `nginx.ingress.kubernetes.io/ssl-redirect` | Automatic (default behavior) | No annotation needed |
| `nginx.ingress.kubernetes.io/proxy-body-size` | `caddy.ingress-controller/proxy-body-size` | e.g., "100m" |
| `nginx.ingress.kubernetes.io/cors-allow-origin` | `caddy.ingress-controller/cors-allow-origin` | Comma-separated list |
| `nginx.ingress.kubernetes.io/configuration-snippet` | `caddy.ingress-controller/response-headers` | Use for custom headers |

### TLS Configuration

**nginx (current)**:
```yaml
spec:
  tls:
  - hosts:
    - searxng.zephyr.lan
    secretName: searxng-tls
```

**Caddy (target)**:
```yaml
# No tls section needed! Caddy provisions automatically
# Just specify the hostname in rules:
spec:
  rules:
  - host: searxng.zephyr.lan
    # ... rest of config
```

---

## Implementation Plan

### Phase 1: Staging Deployment (Day 1-2)

**Objective**: Deploy Caddy with Let's Encrypt staging, validate with one service

**Steps**:
1. Create namespace `caddy-ingress`
2. Deploy caddy-ingress controller with staging enabled
3. Create IngressClass `caddy`
4. Update `mlflow-ingress` to use caddy class
5. Verify staging certificate provisioning
6. Load test with `ab -n 10000 -c 10 http://mlflow.cluster.local/`

**Validation**:
- [ ] Caddy pods running (3/3 ready)
- [ ] Staging certificate issued
- [ ] HTTP → HTTPS redirect working
- [ ] Backend service accessible
- [ ] Load test passes (p99 < 200ms)

**Rollback**: If failed, switch mlflow-ingress back to nginx class, delete caddy deployment

---

### Phase 2: Parallel Migration (Day 3-5)

**Objective**: Migrate all services one by one, running both controllers

**Steps**:
1. Deploy production caddy-ingress (staging=false)
2. **Service 1**: Update `searxng` Ingress to caddy class
   - Monitor for 4 hours
   - Check metrics, logs, certificate
3. **Service 2**: Update `akash-hostname-operator` to caddy class
   - Monitor for 4 hours
4. **Service 3**: Update `akash-provider-v2-letsencrypt-challenge` to caddy class
   - Monitor for 4 hours
5. **Service 4**: Update `mlflow-ingress` to caddy class
   - Monitor for 4 hours

**Monitoring**:
```bash
# Watch Caddy logs
kubectl logs -f -n caddy-ingress deployment/caddy-ingress-controller

# Check certificate status
kubectl get secrets -n caddy-ingress

# Ingress metrics
kubectl get ingress -A
```

**Validation**:
- [ ] All 4 ingress resources using caddy class
- [ ] Certificates provisioned for all hostnames
- [ ] No increase in error rate
- [ ] No increase in latency (p99)

**Rollback**: If any service fails, switch that specific Ingress back to nginx class

---

### Phase 3: Full Cutover (Day 6-7)

**Objective**: Remove nginx-ingress, make Caddy the default

**Steps**:
1. Monitor all services for 24 hours with Caddy
2. Mark `caddy` IngressClass as default
3. Remove nginx-ingress deployment
4. Remove nginx ingress class
5. Update documentation

**Final Validation**:
- [ ] nginx-ingress pods terminated
- [ ] Caddy is default IngressClass
- [ ] All services operational
- [ ] Certificate renewal working (check in 30 days)

---

## Success Criteria

### Functional Requirements

- [ ] All 4 ingress resources functional with Caddy
- [ ] Automatic HTTPS working for all hostnames
- [ ] HTTP → HTTPS redirect enforced
- [ ] WebSocket support maintained
- [ ] HTTP/2 support maintained

### Performance Requirements

- [ ] p99 latency < 200ms (baseline from nginx)
- [ ] No increase in error rate (> 1%)
- [ ] Certificate provisioning < 30s
- [ ] Zero downtime during migration

### Operational Requirements

- [ ] Certificate auto-renewal working
- [ ] Monitoring and alerting configured
- [ ] Rollback plan tested
- [ ] Documentation updated

---

## Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Let's Encrypt rate limit | Medium | High | Use staging for testing, stagger certificate requests |
| Caddy controller bug | Low | High | Parallel deployment with nginx, quick rollback |
| Annotation incompatibility | Low | Medium | Document annotation migration, test in staging |
| Performance regression | Low | High | Load testing in staging, monitor p99 latency |
| DNS propagation delay | Low | Low | Use low TTL (300s) during migration |

---

## Post-Migration Tasks

1. **Certificate Monitoring**:
   - Set up alerts for certificate expiration (30 days before)
   - Monitor Let's Encrypt rate limit usage
   - Dashboard for certificate status

2. **Documentation**:
   - Update cluster documentation
   - Create runbook for certificate management
   - Document Caddy-specific troubleshooting

3. **Cleanup**:
   - Remove old nginx-ingress manifests
   - Archive nginx configuration
   - Update GitOps repository

4. **Optimization**:
   - Tune Caddy performance based on metrics
   - Adjust resource limits if needed
   - Implement HTTP/3 support if needed

---

## Appendix: Commands Reference

### Deployment
```bash
kubectl apply -f kubernetes-manifests/ingress/caddy/
```

### Validation
```bash
# Check Caddy status
kubectl get pods -n caddy-ingress
kubectl logs -n caddy-ingress deployment/caddy-ingress-controller

# Check certificates
kubectl get secrets -n caddy-ingress
kubectl describe secret <ingress-name>-tls -n caddy-ingress

# Test ingress
curl -I https://mlflow.cluster.local
curl -I https://searxng.zephyr.lan
```

### Rollback
```bash
# Switch back to nginx
kubectl patch ingress <ingress-name> -p '{"spec":{"ingressClassName":"nginx"}}'

# Remove Caddy
kubectl delete -f kubernetes-manifests/ingress/caddy/
```

---

**Document Status**: ✅ Design Complete
**Next Step**: Invoke writing-plans skill to create detailed implementation plan
**Target Implementation Date**: 2026-03-29
