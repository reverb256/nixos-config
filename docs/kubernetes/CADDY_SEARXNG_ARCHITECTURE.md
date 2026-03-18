# Caddy + SearXNG + AI Gateway - Complete Architecture

**Date:** 2026-03-17
**Status:** ✅ Fully Operational

---

## 🏗️ **ARCHITECTURE OVERVIEW**

```
┌─────────────────────────────────────────────────────────────────┐
│                        EXTERNAL ACCESS                          │
└──────────────┬──────────────┬──────────────┬────────────────────┘
               │              │              │
         ┌─────▼─────┐  ┌─────▼─────┐  ┌────▼──────┐
         │  Nexus    │  │   Forge   │  │  Sentry  │
         │ 10.1.1.120│  │10.1.1.130 │  │10.1.1.140 │
         │  :80/:443 │  │  :80/:443 │  │  :80/:443 │
         └─────┬─────┘  └─────┬─────┘  └────┬──────┘
               │              │              │
               └──────────────┼──────────────┘
                              │
                    ┌─────────▼──────────┐
                    │  CADDY INGRESS     │
                    │  Controller (K8s)  │
                    │  - 3 replicas       │
                    │  - DaemonSet        │
                    │  - Auto HTTPS       │
                    │  - Load Balancing   │
                    └─────────┬──────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   ┌────▼────────┐     ┌──────▼──────┐     ┌──────▼─────┐
   │  CLUSTER    │     │   EXTERNAL  │     │  ZEPHYR    │
   │  SERVICES   │     │   SERVICES  │     │  (HOST)    │
   │  (K8s SVC)  │     │   (HOST IP) │     │            │
   └────┬────────┘     └──────┬──────┘     └──────┬─────┘
        │                     │                     │
   ┌────▼────────┐     ┌──────▼──────┐     ┌──────▼─────┐
   │ Akash       │     │  SearXNG    │     │  AI Gateway │
   │ Provider    │     │  (NixOS)    │     │  (NixOS)    │
   │ :8443       │     │  :7777      │     │  :8080      │
   └─────────────┘     └─────────────┘     └─────────────┘
```

---

## 🎯 **COMPONENT DETAILS**

### **1. Caddy Ingress Controller (Kubernetes)**

**Deployment:** DaemonSet with 3 replicas
- **Nexus** (10.1.1.120) - Storage node
- **Forge** (10.1.1.130) - GPU node
- **Sentry** (10.1.1.140) - Monitoring node

**Not on Zephyr** (control plane) - avoids resource contention

**Services:**
```yaml
caddy-ingress:
  type: NodePort
  ports:
    - 80:30080  (HTTP)
    - 443:30443 (HTTPS)

caddy-ingress-internal:
  type: ClusterIP
  ports:
    - 80   (HTTP)
    - 443  (HTTPS)

caddy-admin:
  type: ClusterIP
  ports:
    - 2019 (Admin API)

caddy-metrics:
  type: ClusterIP
  ports:
    - 2019 (Prometheus metrics)
```

**Configuration:** ConfigMap `caddy-config` in `ingress-system` namespace
- **Caddyfile format:** Human-readable, simple
- **TLS:** Internal certificates for `.cluster.local`
- **Load balancing:** Round-robin (default)
- **Health checks:** Built-in passive checks

**IngressClass:** `caddy` (marked as default)
```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: caddy
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: caddy-labs.ingress-controller/k8s-ingress-controller
```

---

### **2. SearXNG (NixOS Service on Zephyr)**

**Deployment:** NixOS systemd service
```nix
services.searxng = {
  enable = true;
  settings = {
    server = {
      secret_key = "@SEARXNG_SECRET_KEY@";
      limiter = false;  # ✅ DISABLED FOR AI USAGE
      image_proxy = true;
    };
    limiter = false;  # ✅ GLOBAL LIMITER DISABLED
  };
};
```

**Access:** Multiple methods
1. **Direct:** `http://10.1.1.110:7777` (Zephyr host IP)
2. **Via Caddy:** `https://searxng.cluster.local` (cluster DNS)
3. **Via Caddy (NodePort):** `http://10.1.1.120:30080` (with Host header)
4. **Via AI Gateway:** `http://10.1.1.110:8080/mcp/call` (MCP protocol)

**Features:**
- 242 search engines
- JSON API (`format=json`)
- Multiple categories (general, images, videos, science, it, etc.)
- Site search (`site:example.com query`)
- Time range filtering (`day`, `week`, `month`, `year`)
- **Rate limiting disabled** for AI agent usage

---

### **3. AI Gateway (NixOS Service on Zephyr)**

**Deployment:** FastAPI application with MCP broker
```nix
services.ai-inference = {
  enable = true;
  gateway = {
    host = "127.0.0.1";
    port = 8080;
    workers = 4;
  };
  mcp = {
    enable = true;
    servers = {
      searxng = {
        type = "local";
        command = ["python3", "-m", "ai_inference_gateway.mcp_servers.searxng_server"];
        environment = {
          SEARXNG_URL = "http://127.0.0.1:7777";  # ✅ Direct access
          SEARXNG_CACHE_TTL = "300";
        };
      };
    };
  };
};
```

**MCP Tools (12 total):**
1. `web_search` - General web search
2. `search_code` - Code repositories (GitHub, GitLab)
3. `search_research` - Academic papers (arXiv, Google Scholar)
4. `search_devops` - DevOps resources (Docker Hub)
5. `search_data` - Data science (Kaggle, Papers with Code)
6. `search_github` - GitHub-specific search
7. `search_nixos_options` - NixOS configuration search
8. `search_mdn` - MDN Web Docs
9. `search_stackoverflow` - Stack Overflow
10. `search_reddit` - Reddit discussions
11. `search_stats` - Search statistics
12. `ping_searxng` - Health check

**Access via Caddy:** `https://ai-gateway.cluster.local`

---

## 🔄 **REQUEST FLOW**

### **Scenario 1: Direct SearXNG Query**

```
User
  │
  ├─► http://10.1.1.110:7777/search?q=test
  │   └─► SearXNG (NixOS service on Zephyr)
  │       └─► Returns JSON results
  │
  └─► Results (242 engines, no rate limiting)
```

### **Scenario 2: SearXNG via Caddy Ingress**

```
User
  │
  ├─► https://searxng.cluster.local/search?q=test
  │   └─► DNS resolves to Caddy NodePort or host port
  │       └─► Caddy (on Nexus/Forge/Sentry)
  │           ├─► TLS termination (internal cert)
  │           ├─► Routing (reverse_proxy to 10.1.1.110:7777)
  │           └─► SearXNG (NixOS service on Zephyr)
  │               └─► Returns JSON results
  │
  └─► Results (with TLS, load balanced)
```

### **Scenario 3: AI Gateway with SearXNG**

```
User (AI Agent/Claude Code)
  │
  ├─► POST http://10.1.1.110:8080/mcp/call
  │   {
  │     "server": "searxng",
  │     "tool": "web_search",
  │     "arguments": {"query": "nixos flakes"}
  │   }
  │   └─► AI Gateway (FastAPI on Zephyr)
  │       ├─► MCP broker dispatches to SearXNG server
  │       ├─► SearXNGIntegration.search()
  │       │   ├─► Cache check (Redis optional)
  │       │   ├─► Quality scoring
  │       │   └─► HTTP GET to SEARXNG_URL
  │       │       └─► http://127.0.0.1:7777/search
  │       │           └─► SearXNG (NixOS service)
  │       │               └─► Returns JSON
  │       ├─► Result processing
  │       │   ├─► Domain routing (code, research, devops, data)
  │       │   ├─► Quality scoring algorithm
  │       │   └─► RAG integration (optional)
  │       └─► Returns formatted results
  │
  └─► Enhanced results (with quality scores, domain detection)
```

### **Scenario 4: Kubernetes Service via Caddy**

```
User
  │
  ├─► https://provider.cluster.local
  │   └─► Caddy (on Nexus/Forge/Sentry)
  │       ├─► TLS termination (internal cert)
  │       ├─► Routing rule matches
  │       └─► reverse_proxy akash-provider.akash-provider.svc.cluster.local:8443
  │           └─► K8s Service (ClusterIP)
  │               └─► Akash Provider pods
  │
  └─► GPU compute marketplace interface
```

---

## 🔐 **SECURITY & TLS**

### **Internal Certificates (.cluster.local)**

**Issuer:** Caddy internal CA
**Auto-renewal:** Yes (every 24 hours)
**Validation:** Internal DNS

**Usage:**
```caddyfile
service.cluster.local {
  tls internal  # ← Uses Caddy's internal CA
  reverse_proxy backend:8080
}
```

### **Public Certificates (Let's Encrypt)**

**For external domains:**
```caddyfile
your-domain.com {
  tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
  }
  reverse_proxy backend:8080
}
```

**DNS Challenge Providers:**
- Cloudflare
- DuckDNS
- Google Cloud DNS
- Route53
- DigitalOcean
- Many more...

---

## 📊 **MONITORING**

### **Caddy Metrics**

**Endpoint:** `caddy-admin.ingress-system.svc.cluster.local:2019/metrics`

**Metrics Available:**
- Request count by status code
- Request duration histograms
- Active connections
- Backend health status

**Prometheus Scrape Config:**
```yaml
scrape_configs:
  - job_name: 'caddy'
    static_configs:
      - targets:
        - caddy-metrics.ingress-system.svc.cluster.local:2019
    metrics_path: /metrics
```

### **SearXNG Health**

**Direct:**
```bash
curl http://10.1.1.110:7777/health
```

**Via AI Gateway:**
```bash
curl -X POST http://10.1.1.110:8080/mcp/call \
  -H 'Content-Type: application/json' \
  -d '{"server":"searxng","tool":"ping_searxng","arguments":{}}'
```

**Returns:**
```json
{
  "status": "healthy",
  "service": "SearXNG",
  "url": "http://127.0.0.1:7777",
  "cache_ttl": 300
}
```

---

## 🚀 **DEPLOYMENT COMMANDS**

### **Update Caddy Configuration**

```bash
# Edit ConfigMap
kubectl edit configmap -n ingress-system caddy-config

# Restart pods (pick up new config)
kubectl rollout restart daemonset/caddy-ingress -n ingress-system

# Verify
kubectl get pods -n ingress-system -l app.kubernetes.io/name=caddy-ingress
```

### **Test SearXNG Routing**

```bash
# Direct (bypasses Caddy)
curl "http://10.1.1.110:7777/search?q=test&format=json" | jq .

# Via Caddy with Host header
curl -H "Host: searxng.cluster.local" http://10.1.1.120/search?q=test

# Via AI Gateway MCP
curl -X POST http://10.1.1.110:8080/mcp/call \
  -H 'Content-Type: application/json' \
  -d '{"server":"searxng","tool":"web_search","arguments":{"query":"nixos"}}' \
  | jq .result
```

### **Scale Caddy**

```bash
# Already DaemonSet (one pod per node)
# To add Caddy to Zephyr (control plane):
kubectl patch daemonset caddy-ingress -n ingress-system --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/affinity"}]'
```

---

## 📚 **RELATED DOCUMENTATION**

- **Migration Guide:** `/etc/nixos/docs/kubernetes/CADDY_INGRESS_MIGRATION_GUIDE.md`
- **SearXNG AI Patterns:** `/etc/nixos/docs/gateway/SEARXNG_AI_PATTERNS_RESEARCH.md`
- **Deployment Status:** `/etc/nixos/docs/gateway/SEARXNG_DEPLOYMENT_STATUS.md`
- **Kubernetes Roadmap:** `/etc/nixos/ROADMAP.md`

---

## ✅ **ADVANTAGES OF THIS ARCHITECTURE**

1. **Separation of Concerns**
   - Caddy: Edge routing, TLS termination
   - SearXNG: Specialized search service
   - AI Gateway: Orchestration and intelligence

2. **High Availability**
   - Caddy runs on all worker nodes (3 replicas)
   - No single point of failure
   - Automatic failover

3. **Performance**
   - Direct access to SearXNG (no extra hops for AI agents)
   - Caddy caching (optional)
   - HTTP/2, HTTP/3 support

4. **Security**
   - Rate limiting disabled for AI usage
   - Internal TLS for cluster communication
   - No external dependencies for search

5. **Scalability**
   - Easy to add more Caddy nodes
   - SearXNG can be scaled (multiple instances)
   - Load balancing built-in

6. **Maintainability**
   - Declarative configuration (NixOS + K8s)
   - GitOps-friendly
   - Rollback capabilities

---

**Status:** ✅ Production-ready architecture
**Next:** Add Let's Encrypt for public domains, set up monitoring dashboards
