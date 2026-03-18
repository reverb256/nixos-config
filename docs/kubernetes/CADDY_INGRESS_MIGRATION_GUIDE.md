# Caddy Ingress Controller - Complete Migration Guide

**Date:** 2026-03-17
**Status:** ✅ Caddy Running in K8s, Configuration Applied
**Caddy Version:** 2.8-alpine (DaemonSet, 3 replicas)

---

## 🎯 **OVERVIEW**

Migrate from NGINX to **Caddy** as the primary ingress controller for Kubernetes workloads. Caddy provides:

- ✅ Automatic HTTPS with Let's Encrypt
- ✅ Simple, human-readable configuration
- ✅ Modern HTTP/2, HTTP/3 support
- ✅ Built-in metrics and admin API
- ✅ Dynamic configuration without restarts

---

## 📊 **CURRENT STATE**

### **Caddy Deployment (Kubernetes)**

**DaemonSet:** `caddy-ingress` in `ingress-system` namespace

**Pods:** 3 replicas (one per worker node)
- `caddy-ingress-*` on Nexus (10.1.1.120)
- `caddy-ingress-*` on Forge (10.1.1.130)
- `caddy-ingress-*` on Sentry (10.1.1.140)

**Services:**
- `caddy-ingress` - NodePort (80:30080, 443:30443)
- `caddy-ingress-internal` - ClusterIP (80, 443)
- `caddy-admin` - ClusterIP (2019) - Admin API
- `caddy-metrics` - ClusterIP (2019) - Prometheus metrics

**Access Methods:**
1. **NodePort:** `http://<worker-ip>:30080` or `https://<worker-ip>:30443`
2. **Host Ports:** Direct access to worker nodes on ports 80/443
3. **Cluster Internal:** Service `caddy-ingress-internal.ingress-system.svc.cluster.local`

### **Current Routes (ConfigMap: `caddy-config`)**

✅ **Internal Services (.cluster.local):**
- `provider.cluster.local` → Akash Provider
- `echo.cluster.local` → Echo test server
- `zephyr.lan` → Zephyr dashboard
- `nexus.lan` → Nexus dashboard
- `forge.lan` → Forge dashboard
- `sentry.lan` → Sentry dashboard

✅ **NEW: SearXNG Integration:**
- `searxng.cluster.local` → SearXNG (10.1.1.110:7777)
- `search.cluster.local` → SearXNG alias
- `ai-gateway.cluster.local` → AI Gateway (10.1.1.110:8080)
- `gateway.cluster.local` → AI Gateway alias

---

## 🚀 **MIGRATION STEPS**

### **Step 1: Apply Caddy IngressClass**

```bash
kubectl apply -f /etc/nixos/modules/services/kubernetes/caddy-ingress-class.yaml
```

**Result:** Creates `caddy` IngressClass, marks as default

**Verification:**
```bash
kubectl get ingressclass
```

Expected output:
```
NAME    CONTROLLER                  PARAMETERS   AGE
caddy   caddy-ingress-controller    <none>       1m
nginx   k8s.io/ingress-nginx         <none>       33h
```

---

### **Step 2: Test SearXNG Through Caddy**

**Option A: Via Cluster DNS (requires DNS configured)**
```bash
curl -k https://searxng.cluster.local/health
curl -k https://search.cluster.local/search?q=test&format=json
```

**Option B: Via Host Header (works immediately)**
```bash
# Via Nexus worker node
curl -H "Host: searxng.cluster.local" http://10.1.1.120/search?q=test

# Via NodePort
curl -H "Host: searxng.cluster.local" http://10.1.1.120:30080/search?q=test
```

**Option C: Via Internal Service**
```bash
# From within cluster
kubectl run test --image=curlimages/curl -i --rm --restart=Never -- \
  curl -H "Host: searxng.cluster.local" http://caddy-ingress-internal.ingress-system.svc.cluster.local/search?q=test
```

---

### **Step 3: Migrate Existing Ingress Resources**

**Before (NGINX):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: app.cluster.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

**After (Caddy):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    kubernetes.io/ingress.class: caddy
spec:
  rules:
  - host: app.cluster.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

**Or use default IngressClass (caddy is marked as default):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  # No ingress.class annotation needed!
spec:
  rules:
  - host: app.cluster.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

---

### **Step 4: Remove NGINX Ingress Controller (Optional)**

**Stop NGINX deployment:**
```bash
kubectl scale deployment ingress-nginx-controller -n ingress-nginx --replicas=0
```

**Remove NGINX entirely:**
```bash
helm uninstall ingress-nginx -n ingress-nginx
# Or if using manifests:
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/cloud/deploy.yaml
```

---

## 🔧 **ADVANCED CONFIGURATION**

### **TLS Configuration**

**Automatic HTTPS (Let's Encrypt):**
```caddyfile
your-domain.com {
  tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    resolvers 1.1.1.1
  }
  reverse_proxy my-service.default.svc.cluster.local:80
}
```

**Internal TLS (cluster.local):**
```caddyfile
service.cluster.local {
  tls internal
  reverse_proxy my-service.default.svc.cluster.local:80
}
```

**Custom Certificates:**
```caddyfile
service.cluster.local {
  tls /path/to/cert.pem /path/to/key.pem
  reverse_proxy my-service.default.svc.cluster.local:80
}
```

---

### **Load Balancing**

**Round Robin (default):**
```caddyfile
api.cluster.local {
  tls internal
  reverse_proxy service1.default.svc.cluster.local:80 \
                 service2.default.svc.cluster.local:80 \
                 service3.default.svc.cluster.local:80
}
```

**Least Connection:**
```caddyfile
api.cluster.local {
  tls internal
  reverse_proxy service1.default.svc.cluster.local:80 \
                 service2.default.svc.cluster.local:80 {
    lb_policy least_connection
  }
}
```

**IP Hash:**
```caddyfile
api.cluster.local {
  tls internal
  reverse_proxy service1:80 service2:80 {
    lb_policy ip_hash
  }
}
```

---

### **Health Checks**

**Passive Health Checks (built-in):**
```caddyfile
api.cluster.local {
  tls internal
  reverse_proxy service1:80 service2:80 {
    health_uri /health
    health_interval 10s
    health_timeout 5s
  }
}
```

**Active Health Checks:**
```caddyfile
api.cluster.local {
  tls internal
  reverse_proxy service1:80 service2:80 {
    health_path /health
    health_port 8080
    health_interval 10s
    health_timeout 5s
    health_status 200
  }
}
```

---

### **Caddy Extensions (Modules)**

**Check available modules:**
```bash
# List installed Caddy modules
docker run caddy:2.8-alpine caddy list-modules
```

**Common extensions:**
- `caddy-dns/cloudflare` - Cloudflare DNS challenge
- `caddy-dns/duckdns` - DuckDNS integration
- `caddy-security` - Security headers
- `caddy-prometheus` - Enhanced metrics
- `caddy-ext-authz` - External authorization

**Enable extension:**
```dockerfile
FROM caddy:2.8-builder AS builder
RUN xcaddy build \
  --with github.com/caddy-dns/cloudflare \
  --with github.com/caddy-dns/duckdns \
  --with github.com/caddy-security

FROM caddy:2.8-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

---

## 📝 **UPDATING CADDY CONFIGURATION**

### **Method 1: Edit ConfigMap Directly**

```bash
kubectl edit configmap -n ingress-system caddy-config
```

Add/edit routes in the Caddyfile section, then restart:
```bash
kubectl rollout restart daemonset/caddy-ingress -n ingress-system
```

### **Method 2: Update from File**

```bash
# Edit Caddyfile locally
vim Caddyfile

# Apply to ConfigMap
kubectl create configmap -n ingress-system caddy-config \
  --from-file=Caddyfile=/path/to/Caddyfile \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart Caddy
kubectl rollout restart daemonset/caddy-ingress -n ingress-system
```

### **Method 3: Using Caddy Admin API (No Restart)**

```bash
# Load new config via admin API
kubectl port-forward -n ingress-system svc/caddy-admin 2019:2019

# In another terminal
curl localhost:2019/load \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "apps": {
      "http": {
        "servers": {
          "srv0": {
            "listen": [":80"],
            "routes": [...]
          }
        }
      }
    }
  }'
```

---

## 🔍 **MONITORING & DEBUGGING**

### **Check Caddy Status**

```bash
# Pod status
kubectl get pods -n ingress-system -l app.kubernetes.io/name=caddy-ingress

# Logs
kubectl logs -n ingress-system -l app.kubernetes.io/name=caddy-ingress --tail=50

# Config validation
kubectl exec -n ingress-system caddy-ingress-<pod> -- caddy validate --config /config/Caddyfile --adapter caddyfile
```

### **Admin API Endpoints**

```bash
# Port forward to admin API
kubectl port-forward -n ingress-system svc/caddy-admin 2019:2019

# Get current config
curl localhost:2019/config/

# Health check
curl localhost:2019/

# Metrics (Prometheus format)
curl localhost:2019/metrics
```

### **Common Issues**

**Issue: "No matching route"**
- Cause: Route not configured in Caddyfile
- Fix: Add route to ConfigMap and restart Caddy

**Issue: "Connection refused"**
- Cause: Backend service not reachable
- Fix: Check service exists, pods are running, network policies allow traffic

**Issue: "TLS handshake error"**
- Cause: Certificate not valid for hostname
- Fix: Use `tls internal` for cluster.local, or configure proper certs

**Issue: "502 Bad Gateway"**
- Cause: Backend service down or wrong port
- Fix: Check backend service health, verify port number

---

## 📚 **EXAMPLE CONFIGURATIONS**

### **SearXNG with AI Gateway**

```caddyfile
# SearXNG search engine
searxng.cluster.local {
  tls internal
  reverse_proxy 10.1.1.110:7777 {
    header_up Host {host}
    header_up User-Agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
  }
}

# AI Gateway with SearXNG backend
ai-gateway.cluster.local {
  tls internal
  reverse_proxy 10.1.1.110:8080 {
    header_up Host {host}
    header_up Connection ">X-Forwarded-For"
  }
}
```

### **Multi-Service API Gateway**

```caddyfile
api.cluster.local {
  tls internal

  # Route by path
  handle /search/* {
    reverse_proxy searxng:7777
  }

  handle /ai/* {
    reverse_proxy ai-gateway:8080
  }

  handle /storage/* {
    reverse_proxy minio:9000
  }

  # Fallback
  respond "Not Found" 404
}
```

### **WebSocket Support**

```caddyfile
websocket.cluster.local {
  tls internal
  reverse_proxy websocket-service:8080 {
    # WebSocket headers
    header_up Upgrade {http.request.header.Upgrade}
    header_up Connection {http.request.header.Connection}
  }
}
```

### **Rate Limiting**

```caddyfile
api.cluster.local {
  tls internal
  reverse_proxy api-service:8080

  # Rate limit by client IP
  @rate_limited {
    rate {remote_host} 100/minute
  }
  respond @rate_limited "Too many requests" 429
}
```

---

## 🎯 **NEXT STEPS**

### **Priority 1: Complete Migration**
- [ ] Apply Caddy IngressClass
- [ ] Test SearXNG routing
- [ ] Update all Ingress resources to use Caddy
- [ ] Remove NGINX ingress controller

### **Priority 2: Add Features**
- [ ] Configure Let's Encrypt for public domains
- [ ] Set up DNS challenge (Cloudflare/DuckDNS)
- [ ] Add Prometheus metrics scraping
- [ ] Create Grafana dashboard

### **Priority 3: Advanced Configuration**
- [ ] Enable Caddy extensions (DNS, security)
- [ ] Set up automatic HTTP→HTTPS redirects
- [ ] Configure request/response rewriting
- [ ] Add authentication middleware

---

## 📖 **REFERENCES**

- **Caddy Docs:** https://caddyserver.com/docs/
- **Caddy JSON Config:** https://caddyserver.com/docs/json/
- **Caddy Modules:** https://caddyserver.com/docs/modules/
- **Kubernetes Ingress:** https://kubernetes.io/docs/concepts/services-networking/ingress/
- **Cluster Documentation:** `/etc/nixos/docs/kubernetes/`

---

## ✅ **VERIFICATION CHECKLIST**

After migration, verify:

- [ ] Caddy pods running (3 replicas)
- [ ] ConfigMap applied correctly
- [ ] IngressClass created
- [ ] DNS resolution working
- [ ] TLS certificates valid
- [ ] Services accessible through Caddy
- [ ] Health checks passing
- [ ] Metrics being collected
- [ ] NGINX removed (if applicable)

---

**Status:** Configuration applied, ready for testing!
**Next:** Apply IngressClass and test routing.
