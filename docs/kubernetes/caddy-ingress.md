# Caddy Ingress Controller - Kubernetes

**Status:** ✅ Production Ready | **Deployed:** 2026-03-14 | **Version:** Caddy 2.8

---

## Overview

Caddy is the ingress controller for the Kubernetes cluster, replacing the original plan to use NGINX Ingress. Caddy provides automatic HTTPS, HTTP/3 support, and simpler configuration compared to NGINX.

**Decision Rationale:**
- **Automatic HTTPS:** Built-in Let's Encrypt integration (no cert-manager needed)
- **HTTP/3 Support:** Native QUIC protocol for improved performance
- **Simpler Config:** Caddyfile is more readable than NGINX annotations
- **Consistency:** Already used for systemd services (existing expertise)

---

## Architecture

```
External Traffic (NodePort 30080/30443)
          ↓
    Caddy DaemonSet (nexus, sentry)
          ↓
    Service Discovery (CoreDNS + Unbound)
          ↓
    Backend Services (ai-inference, searxng, etc.)
```

**Deployment Model:** DaemonSet (runs on all Ready nodes)

**Node Placement:**
| Node | Caddy Pod | Status |
|------|-----------|--------|
| Zephyr | Skipped | Control-plane node, systemd Caddy still active |
| Nexus | ✅ Running | Worker node |
| Forge | Skipped | NotReady state |
| Sentry | ✅ Running | Worker node |

---

## Configuration

### Files

| File | Purpose |
|------|---------|
| `kubernetes-manifests/ingress/00-namespace.yaml` | Namespace |
| `kubernetes-manifests/ingress/01-serviceaccount.yaml` | RBAC |
| `kubernetes-manifests/ingress/02-configmap.yaml` | Caddyfile routes |
| `kubernetes-manifests/ingress/03-daemonset.yaml` | Caddy pods |
| `kubernetes-manifests/ingress/04-service.yaml` | Services |
| `kubernetes-manifests/ingress/05-priorityclass.yaml` | Scheduling priority |
| `kubernetes-manifests/ingress/08-metrics-service.yaml` | Prometheus scraping |

### Network Ports

| Port | Purpose | External Access |
|------|---------|------------------|
| 80 | HTTP | NodePort 30080 |
| 443 | HTTPS | NodePort 30443 (TCP/UDP) |
| 2019 | Admin API + Metrics | ClusterIP only |

---

## Routes

### Internal Services (.cluster.local)

| Route | Backend | Status |
|-------|---------|--------|
| `ai.cluster.local` | `ai-inference:8080` | ⏳ Backend not deployed |
| `ai.zephyr.cluster.local` | `ai-inference:8080` | ⏳ Backend not deployed |
| `search.cluster.local` | `searxng:7777` | ⏳ Backend not deployed |
| `echo.cluster.local` | `echo-server:80` | ✅ Test service working |

### Tailscale Services (.ts.net)

| Route | Backend | TLS |
|-------|---------|-----|
| `ai.zephyr.tigris-ule.ts.net:9002` | `ai-inference:8080` | Internal |
| `search.zephyr.tigris-ule.ts.net:9001` | `searxng:7777` | Internal |
| `vaultwarden.zephyr.tigris-ule.ts.net` | `vaultwarden:80` | Internal |
| `glitchtip.zephyr.tigris-ule.ts.net` | `glitchtip-web:8000` | Internal |

### Akash Provider

| Route | Backend | Purpose |
|-------|---------|---------|
| `provider.cluster.local` | `akash-provider:8443` | GPU compute marketplace |

---

## Management

### Deploy

```bash
kubectl apply -f /etc/nixos/kubernetes-manifests/ingress/
```

### Check Status

```bash
# Pods
kubectl -n ingress-system get pods -o wide

# Services
kubectl -n ingress-system get svc

# Logs
kubectl -n ingress-system logs -l app.kubernetes.io/name=caddy-ingress

# Metrics (via pod)
kubectl -n ingress-system exec -l app.kubernetes.io/name=caddy-ingress -- \
    curl -s http://localhost:2019/metrics
```

### Update Routes

1. Edit `02-configmap.yaml`
2. Apply: `kubectl apply -f 02-configmap.yaml`
3. Restart: `kubectl -n ingress-system rollout restart daemonset/caddy-ingress`

### Test Routing

```bash
# Port-forward test
kubectl -n ingress-system port-forward svc/caddy-ingress-internal 8080:80
curl -H "Host: echo.cluster.local" http://localhost:8080/

# NodePort test
curl -H "Host: echo.cluster.local" http://10.1.1.120:30080/

# HTTPS test (with -k to skip cert verification)
curl -k -H "Host: echo.cluster.local" https://10.1.1.120:30443/
```

---

## Monitoring

### Prometheus Metrics

Caddy exposes Prometheus metrics on the admin API endpoint:

```bash
# Metrics endpoint
curl http://10.1.1.120:2019/metrics
```

**Scrape Configuration:**
- Job: `caddy-ingress`
- Targets: `nexus:2019`, `sentry:2019`
- Path: `/metrics`
- Interval: 15s (default)

**Key Metrics:**
- `caddy_admin_api_requests_total` - Admin API request count
- `http_request_duration_seconds` - Request latency
- `caddy_http_response_count_bytes` - Response sizes

### Grafana Dashboard

Create a dashboard in Grafana using these queries:

```
# Request rate by service
sum(rate(http_requests_in_flight{job="caddy-ingress"}[5m])) by (host)

# Response time histogram
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Active connections
http_requests_in_flight{job="caddy-ingress"}
```

---

## TLS Certificates

### Internal Services (.cluster.local)

Caddy uses its **internal CA** for cluster-local domains:
- Automatic certificate generation
- No external CA needed
- Certificates stored in `/data` (emptyDir)

### Adding TLS for Public Domains

```caddy
# Example: Public domain with Let's Encrypt
your-domain.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    reverse_proxy backend:8080
}
```

**Requirements:**
1. Public DNS A/AAAA record pointing to Node IPs
2. `CLOUDFLARE_API_TOKEN` secret in Kubernetes
3. Update global email in Caddyfile

---

## Troubleshooting

### Pods Not Starting

```bash
# Check events
kubectl -n ingress-system describe pod <pod-name>

# Check init container logs
kubectl -n ingress-system logs <pod-name> -c setup-caddy

# Check main container logs
kubectl -n ingress-system logs <pod-name> --previous
```

### 502 Bad Gateway

```bash
# Verify backend service exists
kubectl get svc -A | grep <backend-name>

# Check service endpoints
kubectl get endpoints -A | grep <backend-name>

# Test backend directly
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
    curl http://<service-name>.<namespace>.svc.cluster.local:<port>/
```

### Certificate Issues

```bash
# Check certificate in use
kubectl -n ingress-system exec -l app.kubernetes.io/name=caddy-ingress -- \
    curl -s http://localhost:2019/config/ | jq '.apps.http.servers.<host>.tls_conn_policies'

# Trust the internal CA (for curl/kubectl)
# Download from: http://10.1.1.120:2019/pki/authorities/local/root.crt
```

### Metrics Not Appearing in Prometheus

```bash
# Check if Prometheus can reach Caddy
curl http://nexus:2019/metrics
curl http://sentry:2019/metrics

# Check Prometheus configuration
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="caddy-ingress")'
```

---

## Migration Notes

### From systemd Caddy

**Before disabling systemd Caddy, ensure:**
1. All services have Kubernetes equivalents deployed
2. DNS records updated (if using public domains)
3. TLS certificates working (or migrated)
4. Monitoring dashboards updated

**Disable systemd Caddy:**
```nix
# In hosts/zephyr/configuration.nix, remove:
services.caddy = {
  enable = true;
  # ...
};
```

---

## References

- [Caddy Documentation](https://caddyserver.com/docs/)
- [Caddy JSON Config Structure](https://caddyserver.com/docs/json/)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- Manifests: `/etc/nixos/kubernetes-manifests/ingress/`
- README: `/etc/nixos/kubernetes-manifests/ingress/README.md`

---

**Last Updated:** 2026-03-14 | **Maintained By:** j_kro
