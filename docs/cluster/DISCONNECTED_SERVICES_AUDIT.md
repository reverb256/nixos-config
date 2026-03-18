# Disconnected Services Audit

**Date:** 2026-03-17 23:45
**Status:** 🔍 Complete Audit
**Scope:** All running but disconnected services

---

## 📊 **SUMMARY**

**Total Discovered:** 7 disconnected services
**Configuration Issues:** 2
**Failing Services:** 2
**Needs Integration:** 3

---

## 🔴 **CRITICAL ISSUES (Fixed)**

### ✅ 1. Redis Middleware (SearXNG Cache) - FIXED
- **Issue:** Environment variable `SEMANTIC_CACHE_ENABLED` not set
- **Root Cause:** NixOS option `gateway.middleware.redis.enable` existed but wasn't wired to the Python code
- **Fix Applied:** Added `SEMANTIC_CACHE_ENABLED = lib.boolToString cfg.gateway.middleware.redis.enable` to gateway.nix
- **Status:** ✅ Configuration fixed, rebuild pending
- **Impact:** After rebuild, AI Gateway will use Redis for caching

### ✅ 2. Backup Service (Garage S3) - FIXED
- **Issue:** Missing secret file `/run/agenix/garage-s3-secret-key`
- **Root Cause:** `storage = false` in agenix-secrets-registry (incorrect comment about Garage location)
- **Fix Applied:** Changed `storage = true` in zephyr configuration
- **Status:** ✅ Configuration fixed, rebuild pending
- **Impact:** After rebuild, automated backups will work

---

## ⚠️ **WORK-IN-PROGRESS FEATURES**

### 3. Hermes Agent - Incomplete Implementation
- **Status:** Enabled but service doesn't exist
- **Issue:** NixOS module creates users/mounts but no systemd service
- **Health Check:** `hermes-health-check.service` fails because no service to monitor
- **Configuration:**
  ```nix
  services.hermes-agent = {
    enable = true;
    user = "j_kro";
    sharedStorage = {
      enable = true;
      mountPoint = "/home/j_kro/.hermes";
      nfsServer = "10.1.1.120";
      nfsPath = "/data/home";
    };
  };
  ```
- **Module Location:** `/etc/nixos/modules/services/hermes-agent/`
- **Missing:** `systemd.services.hermes-agent` definition in default.nix
- **Impact:** Health check timer runs every 30 minutes and fails
- **Recommendation:** Complete the hermes-agent systemd service implementation or disable health check until ready

---

## 🔌 **RUNNING BUT NOT INTEGRATED**

### 4. Glitchtip (Error Tracking)
- **Port:** 8000
- **Process:** `granion --interface asginl glitchtip.asgi:application`
- **User:** Running as UID 5000 (untracked user)
- **Status:** Running but no services configured to use it
- **Configuration:** None found in NixOS configs
- **Impact:** Error tracking available but unused
- **Recommendation:** Either configure AI Gateway to send errors to Glitchtip or document how to use it

### 5. Llama Server (LLM Inference)
- **Port:** 8083
- **Process:** `llama-server` (PID 2917354)
- **Status:** Running manually (no systemd service)
- **Started:** 15h ago (at system boot 08:14)
- **No Integration:** Not exposed via AI Gateway, ingress, or documented
- **Impact:** Available but inaccessible to standard workflows
- **Recommendation:**
  - Create systemd service for llama-server
  - Add to AI Gateway backend options
  - Or integrate as failover backend

### 6. Host Dashboard (Web Interface)
- **Port:** 8090
- **Process:** `python3 -m http.server 8090`
- **Directory:** `/var/lib/host-dashboard`
- **Health Check:** `host-dashboard-setup.service` exists but inactive
- **Status:** Serving files locally but not monitored
- **Impact:** Dashboard accessible but not integrated with monitoring
- **Recommendation:** Activate host-dashboard-setup.service or remove if not needed

---

## ⏭️ **KUBERNETES ISSUES**

### 7. Akash Provider (GPU Marketplace) - USER REQUESTED IGNORE
- **Namespace:** `akash-provider`
- **Issues:**
  - `akash-provider-0`: Pending 27h
  - `cert-helper`: Error 34h
  - `provider-debug-gateway-removed`: Error 45h
- **Action:** User requested to ignore Akash issues
- **Note:** Akash provider exists but not functional

---

## 📈 **MONITORING STACK (All Operational)**

### ✅ Fully Integrated Services
- **Prometheus:** 127.0.0.1:9090 (Active)
- **Grafana:** Active (Authenticated)
- **Node Exporter:** 127.0.0.1:9100 (Active)
- **NVIDIA GPU Exporter:** Active
- **Redis Exporter:** Active
- **Mining Exporter:** Active
- **All scraping:** Configured and working

---

## 🔧 **FIXES APPLIED**

### File: `/etc/nixos/modules/services/ai-inference/gateway.nix`
```diff
+ # Semantic cache configuration (Redis + Qdrant)
+ SEMANTIC_CACHE_ENABLED = lib.boolToString cfg.gateway.middleware.redis.enable;
```

### File: `/etc/nixos/hosts/zephyr/configuration.nix`
```diff
- storage = false;     # Garage runs on nexus, not zephyr
+ storage = true;      # Required for backup-to-garage service (S3 API key)
```

---

## 🚀 **NEXT STEPS**

### Immediate (After Rebuild)
1. ✅ Rebuild NixOS to apply Redis middleware fix
2. ✅ Rebuild NixOS to deploy garage-s3-secret-key
3. ✅ Verify backup-to-garage.service runs successfully
4. ✅ Verify AI Gateway connects to Redis (check `redis-cli CLIENT LIST`)

### Short Term
1. **Complete Hermes Agent:** Add systemd service to hermes-agent module
2. **Integrate Llama Server:** Create systemd service and AI Gateway backend
3. **Configure Glitchtip:** Set up AI Gateway error reporting
4. **Fix Host Dashboard:** Enable health monitoring

### Long Term
1. **Service Registry:** Create centralized inventory of all services
2. **Integration Testing:** Automated tests for service connectivity
3. **Documentation:** Service architecture and integration patterns
4. **Monitoring Dashboards:** Grafana dashboards for all services

---

## 📝 **NOTES**

### Redis Middleware Details
- **Redis Server:** Running (127.0.0.1:6379)
- **Required By:** Semantic cache for SearXNG search results
- **Benefits:**
  - Reduced SearXNG API calls
  - Faster repeated queries
  - Lower latency for AI agents
- **Dependencies:** Qdrant (vector DB) also required for semantic search

### Backup Service Details
- **Schedule:** Daily at 02:00 (2 AM)
- **Retention:** 30 days
- **Backs Up:**
  - `/etc/nixos` (NixOS configuration)
  - `/data/shared` (shared data)
- **Destination:** Garage S3 bucket `backups://`
- **Endpoint:** http://10.1.1.110:3900

### Hermes Agent Details
- **Purpose:** Multi-host orchestration agent
- **Protocol:** MCP (Model Context Protocol)
- **Storage:** NFS mount from Nexus (10.1.1.120:/data/home)
- **Skills:** Custom NixOS-specific skills in `/etc/nixos/modules/services/hermes-agent/skills/`
- **AI Gateway Integration:** Configured to use local AI Gateway
- **Terminal Access:** Enabled (no approval required)

---

**Audit Completed:** 2026-03-17 23:45
**Configuration Changes:** 2 fixes applied
**Services Requiring Integration:** 3
**Services Requiring Completion:** 1 (Hermes Agent)
**Rebuild Required:** Yes (to apply fixes)
