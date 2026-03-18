# SearXNG Multi-Instance Cluster - Deployment Guide

**Status:** 🚀 Ready to Deploy | **Updated:** 2026-03-17
**Estimated Deployment Time:** 30-45 minutes

---

## 📋 **DEPLOYMENT OVERVIEW**

This guide covers deploying the upgraded SearXNG cluster with:
- **3 SearXNG instances** behind NGINX load balancer
- **Redis/Valkey** shared caching
- **AI-optimized routing** with domain-aware search
- **Prometheus metrics** and health monitoring
- **12 specialized search tools** (4 domain-specific + 8 site-specific)

---

## 🎯 **PRE-DEPLOYMENT CHECKLIST**

### **System Requirements**
- ✅ NixOS 24.11+ (current system: NixOS)
- ✅ 4GB+ RAM available
- ✅ 10GB+ disk space
- ✅ Docker & Docker Compose installed
- ✅ Ports available: 6379, 7777-7779, 8888, 9090

### **Verify Docker Installation**
```bash
docker --version
docker-compose --version
# Or use: docker compose version
```

If not installed, add to your NixOS configuration:
```nix
# In /etc/nixos/configuration.nix
virtualisation.docker = {
  enable = true;
  enableOnBoot = true;
};
```

Then rebuild:
```bash
cd /etc/nixos
sudo nixos-rebuild switch
```

---

## 🚀 **DEPLOYMENT STEPS**

### **Step 1: Prepare Environment**

```bash
# Navigate to deployment directory
cd /etc/nixos/docker-compose/searxng-cluster

# Generate secret key
SECRET_KEY=$(openssl rand -hex 32)

# Create .env file
cat > .env <<EOF
SEARXNG_SECRET=$SECRET_KEY
EOF

# Copy SearXNG settings
mkdir -p config
cp ../../modules/services/ai-inference/ai_inference_gateway/mcp_servers/searxng_settings.yml \
   config/searxng_settings.yml

# Make deployment script executable
chmod +x deploy.sh
```

### **Step 2: Deploy SearXNG Cluster**

```bash
# Start the cluster
./deploy.sh start

# Expected output:
# [INFO] Starting SearXNG cluster...
# [INFO] Waiting for services to be healthy...
# ✓ NGINX Load Balancer: healthy
# ✓ SearXNG (port 7777): healthy
# ✓ SearXNG (port 7778): healthy
# ✓ SearXNG (port 7779): healthy
# ✓ Valkey: healthy
```

### **Step 3: Verify Deployment**

```bash
# Check cluster status
./deploy.sh status

# Test search functionality
./deploy.sh test "nixos configuration"

# View logs
./deploy.sh logs
```

### **Step 4: Update AI Gateway Configuration**

The SearXNG integration will automatically connect to the load balancer.

**Current Configuration (Single Instance):**
```python
SEARXNG_URL = "http://127.0.0.1:7777"
```

**Updated Configuration (Multi-Instance):**
```python
SEARXNG_URL = "http://127.0.0.1:8888"  # NGINX load balancer
```

The AI Gateway will automatically:
- Load balance requests across 3 instances
- Use shared Redis/Valkey cache
- Apply domain-aware routing
- Collect Prometheus metrics

---

## 🔧 **CONFIGURATION OPTIONS**

### **Load Balancer Endpoints**

| Endpoint | Purpose |
|----------|---------|
| `http://localhost:8888/` | Main search endpoint (load balanced) |
| `http://localhost:8888/health` | Load balancer health check |
| `http://localhost:8888/nginx_status` | NGINX stats (requires localhost access) |
| `http://localhost:8888/upstream_health` | Upstream instance health |

### **Direct Instance Access** (for debugging)

| Instance | Port | Purpose |
|----------|------|---------|
| SearXNG #1 | 7777 | Primary instance (highest weight) |
| SearXNG #2 | 7778 | Secondary instance |
| SearXNG #3 | 7779 | Tertiary instance |

### **SearXNG Tools Available**

#### **Domain-Specific (AI-Optimized)**
```python
search_code(query, max_results=10)
# Routes to: GitHub, StackOverflow, GitLab, developer docs
# Quality scoring: Code snippet detection, freshness, domain authority

search_research(query, max_results=10)
# Routes to: Google Scholar, ArXiv, Semantic Scholar, academic sources
# Quality scoring: Academic authority, citation count, relevance

search_devops(query, max_results=10)
# Routes to: Docker Hub, Kubernetes docs, GitLab, infrastructure sources
# Quality scoring: Technical accuracy, version recency, practical examples

search_data(query, max_results=10)
# Routes to: HuggingFace, Kaggle, ArXiv ML, AI repositories
# Quality scoring: Dataset quality, model benchmarks, documentation
```

#### **Site-Specific**
```python
search_github(query, max_results=10)
search_nixos_options(query, max_results=10)
search_mdn(query, max_results=10)
search_stackoverflow(query, max_results=10)
search_reddit(query, max_results=10)
```

#### **General**
```python
web_search(query, category="general", max_results=10, language="all")
```

#### **Utility**
```python
search_stats()  # View learning statistics
clear_search_cache()  # Clear cache
ping_searxng()  # Health check
```

---

## 📊 **MONITORING**

### **Prometheus Metrics**

Metrics available at `http://localhost:9090/metrics` (if enabled):

```
# Request metrics
searxng_search_requests_total{category="general", domain="code", engine="github"}
searxng_search_duration_seconds{category="general", domain="code"}

# Cache metrics
searxng_cache_hits_total
searxng_cache_misses_total
searxng_cache_size

# Engine metrics
searxng_active_engines
searxng_engine_success_rate{engine="google"}

# Result quality
searxng_result_quality_score{domain="code"}
```

### **Health Checks**

```bash
# Overall health
curl http://localhost:8888/health

# Upstream status
curl http://localhost:8888/upstream_health

# Cache statistics
curl http://localhost:8888/cache_stats

# Or use the deployment script
./deploy.sh status
```

### **Performance Monitoring**

```bash
# View cache statistics
./deploy.sh stats

# Expected output:
# [INFO] Valkey cache statistics:
# keys=152
# hits=1245
# misses=234
# hit_rate=84.1%
```

---

## 🎛️ **MANAGEMENT COMMANDS**

```bash
# Start cluster
./deploy.sh start

# Stop cluster
./deploy.sh stop

# Restart cluster
./deploy.sh restart

# View status
./deploy.sh status

# View logs (all services)
./deploy.sh logs

# View logs for specific service
./deploy.sh logs searxng-1

# Test search
./deploy.sh test "your query here"

# Clear cache
./deploy.sh cache-clear

# View cache statistics
./deploy.sh stats

# Update to latest images
./deploy.sh update

# Complete cleanup (removes all data)
./deploy.sh cleanup
```

---

## 🔍 **TROUBLESHOOTING**

### **Issue: Services won't start**

**Symptoms:**
```
ERROR: for searxng-1  Cannot start service searxng-1
```

**Solution:**
```bash
# Check port conflicts
sudo netstat -tulpn | grep -E '7777|7778|7779|8888|6379'

# Stop conflicting services
sudo systemctl stop searxng  # If running as systemd service

# Check Docker
docker ps -a
docker logs searxng-1
```

### **Issue: High memory usage**

**Symptoms:**
Valkey using more than 256MB

**Solution:**
Edit `docker-compose.yml` and adjust Valkey command:
```yaml
--maxmemory 512mb  # Increase or decrease as needed
```

Then restart:
```bash
./deploy.sh restart
```

### **Issue: Search returns no results**

**Symptoms:**
All searches return empty results

**Solution:**
```bash
# Check SearXNG health
curl http://localhost:7777/search?q=test&format=json

# Check settings.yml
cat config/searxng_settings.yml | grep -A 5 "disabled:"

# Verify engines are enabled
# If disabled: false, engines are enabled

# Check logs
./deploy.sh logs searxng-1 | grep -i error
```

### **Issue: Load balancer not distributing requests**

**Symptoms:**
All requests go to single instance

**Solution:**
```bash
# Check NGINX configuration
docker exec nginx-lb nginx -t

# View NGINX logs
./deploy.sh logs nginx

# Verify upstream health
curl http://localhost:8888/upstream_health
```

---

## 📈 **PERFORMANCE EXPECTATIONS**

### **Single Instance (Before)**
- Throughput: 10-20 req/s
- Latency: 2-5s (p95)
- Cache: Local memory only

### **Multi-Instance Cluster (After)**
- Throughput: **50-100 req/s** (5-10x improvement)
- Latency: **1-2s** (p95, cached: <100ms)
- Cache: Persistent, shared across instances
- Availability: Graceful degradation

### **Resource Usage**

| Service | CPU | Memory | Disk |
|---------|-----|--------|------|
| SearXNG x3 | 10-20% | 150MB each | 100MB each |
| Valkey | 5-10% | 256MB | 50MB |
| NGINX | 2-5% | 20MB | 10MB |
| **Total** | **20-40%** | **~750MB** | **~400MB** |

---

## 🔐 **SECURITY CONSIDERATIONS**

### **Production Deployment**

1. **Change Secret Keys**
   ```bash
   # Generate new secret
   openssl rand -hex 32

   # Update .env file
   SEARXNG_SECRET=<new-secret>
   ```

2. **Restrict Network Access**
   ```yaml
   # In docker-compose.yml, change:
   ports:
     - "127.0.0.1:8888:80"  # Only localhost
     # Instead of: - "8888:80"
   ```

3. **Enable HTTPS**
   ```bash
   # Add reverse proxy with SSL
   # Or use NGINX in front with Let's Encrypt
   ```

4. **Rate Limiting**
   ```nginx
   # Already configured in nginx.conf
   # Adjust limit_req_zone for your needs
   limit_req_zone $binary_remote_addr zone=searxng_limit:10m rate=10r/s;
   ```

---

## 🔄 **UPGRADING**

### **Update SearXNG Images**

```bash
# Pull latest images
docker pull docker.io/searxng/searxng:latest

# Restart cluster
./deploy.sh restart

# Or use the update command
./deploy.sh update
```

### **Update Configuration**

```bash
# Edit settings.yml
nano config/searxng_settings.yml

# Restart cluster
./deploy.sh restart
```

---

## 📚 **REFERENCE DOCUMENTATION**

- **Main Guide:** `/etc/nixos/docs/gateway/SEARXNG_UPGRADE_GUIDE.md`
- **Setup Docs:** `/etc/nixos/docs/gateway/SEARXNG_DEFAULT_SEARCH.md`
- **SearXNG Official:** https://docs.searxng.org/
- **Docker Hub:** https://hub.docker.com/r/searxng/searxng
- **GitHub:** https://github.com/searxng/searxng

---

## ✅ **DEPLOYMENT VERIFICATION**

Run these commands to verify successful deployment:

```bash
# 1. Check cluster status
./deploy.sh status
# Expected: All services healthy

# 2. Test search
./deploy.sh test "nixos flake"
# Expected: Results returned

# 3. Verify cache
./deploy.sh stats
# Expected: Cache statistics shown

# 4. Check load balancing
curl http://localhost:8888/upstream_health
# Expected: JSON with instance status

# 5. Test AI-optimized search
# Use via MCP tools:
search_code "docker compose example"
search_research "transformer architecture"
search_devops "kubernetes deployment"
search_data "huggingface model"
# Expected: Quality-scored results with domain routing
```

---

## 🎯 **SUCCESS CRITERIA**

### **Functional**
- ✅ All 3 SearXNG instances healthy
- ✅ NGINX load balancing operational
- ✅ Valkey caching functional
- ✅ All 12 search tools working
- ✅ Domain-aware routing functional

### **Performance**
- ✅ Cache hit rate >60%
- ✅ Search latency <3s (p95)
- ✅ Cached queries <100ms
- ✅ Zero data loss on restart

### **Reliability**
- ✅ Graceful degradation when instance fails
- ✅ Automatic failover
- ✅ Health monitoring active
- ✅ Metrics collection working

---

**Status:** ✅ All phases implemented and ready for deployment!
**Next Steps:** Run deployment script and verify functionality
