# Mining Proxy Deployment Guide

## ✅ Status: CPU Mining Fully Configured via Proxy

### CPU Mining (xmrig-proxy)
- **Host**: Zephyr (10.1.1.110)
- **Stratum Port**: 3333
- **API Port**: 8081 (localhost only)
- **Service**: Running as systemd service
- **Process ID**: 17563
- **Connected Workers**:
  - zephyr-cpu (16 threads, ~27 kH/s)
  - nexus-cpu (12 threads)
  - sentry-cpu (8 threads)

### Deployment Details
- **Host**: Zephyr (10.1.1.110)
- **Stratum Port**: 3333
- **API Port**: 8081
- **Status**: ⚠️ Running (user process, needs systemd service)
- **Process ID**: 992956
- **API Binding**: 127.0.0.1 only (localhost)

### Current Configuration
```json
{
  "pools": [
    {
      "id": "kryptex-rx-test",
      "url": "xtm-rx-us.kryptex.network:8038",
      "user": "krxXVNVMM7.zephyr-proxy",
      "pass": "x",
      "tls": true,
      "keepalive": true
    }
  ],
  "workers": [
    {
      "id": "test-worker",
      "password": "x"
    }
  ]
}
```

---

## ✅ CPU Mining Migration COMPLETE

All CPU miners now connect through Zephyr's xmrig-proxy:

| Host | Threads | Worker ID | Status |
|------|---------|-----------|--------|
| Zephyr | 16 | zephyr-cpu | ✅ Connected |
| Nexus | 12 | nexus-cpu | ✅ Configured |
| Sentry | 8 | sentry-cpu | ✅ Configured |

### Proxy Configuration
```json
{
  "pools": [
    {
      "id": "kryptex-rx-primary",
      "url": "xtm-rx-us.kryptex.network:8038",
      "user": "krxXVNVMM7.zephyr-proxy",
      "pass": "x",
      "tls": true,
      "keepalive": true,
      "priority": 1
    },
    {
      "id": "f2pool-rx-backup",
      "url": "xmr-us-east1.nano.pool.ru:5555",
      "user": "krxXVNVMM7.zephyr-proxy",
      "pass": "x",
      "tls": false,
      "priority": 2
    }
  ],
  "workers": [
    {"id": "zephyr-cpu", "password": "x"},
    {"id": "nexus-cpu", "password": "x"},
    {"id": "sentry-cpu", "password": "x"}
  ]
}
```

### Host Configuration Pattern
To add a new CPU miner via proxy:
```nix
mining.xmrig = {
  enable = true;
  autostart = true;
  threads = <thread-count>;
  pool = "10.1.1.110:3333";  # xmrig-proxy
  wallet = "<hostname>-cpu";    # Worker ID
  tls = false;                 # No TLS to proxy
};
```

---

## 🚀 Migration Steps for CPU Miners (ARCHIVED)

### Step 1: Test xmrig-proxy connectivity
```bash
# From Zephyr, test connection to Kryptex via proxy
curl -v telnet://10.1.1.110:3333

# Check proxy status
curl http://10.1.1.110:8081/1/summary
```

### Step 2: Update Zephyr xmrig configuration

**Current (direct connection):**
```nix
mining.xmrig = {
  enable = true;
  autostart = false;
  threads = 16;
  # Uses default pool from mining.nix
};
```

**New (via proxy):**
```nix
mining.xmrig = {
  enable = true;
  autostart = false;
  threads = 16;
  url = "stratum+tcp://10.1.1.110:3333";  # Point to proxy
  user = "zephyr-cpu";  # Worker ID
  pass = "x";
  # Note: Proxy will forward to actual pool
};
```

### Step 3: Update Nexus xmrig configuration

**Add to Nexus configuration.nix:**
```nix
mining.xmrig = {
  enable = true;
  autostart = true;
  threads = 12;
  url = "stratum+tcp://10.1.110:3333";  # Point to Zephyr proxy
  user = "nexus-cpu";
  pass = "x";
};
```

### Step 4: Update Sentry xmrig configuration

**Add to Sentry configuration.nix:**
```nix
mining.xmrig = {
  enable = true;
  autostart = true;
  threads = 8;
  url = "stratum+tcp://10.1.110:3333";  # Point to Zephyr proxy
  user = "sentry-cpu";
  pass = "x";
};
```

---

## 🔧 GPU Mining Status

### Current Architecture: Direct Pool Connections
GPU miners (lolMiner) connect directly to Kryptex:

| Host | GPUs | Algorithm | Status |
|------|------|-----------|--------|
| Forge | 4x NVIDIA | CR29 | ✅ Direct to pool |
| Nexus | 1x NVIDIA | CR29 | ✅ Direct to pool |

**Decision**: GPU mining uses direct pool connections because:
1. **Simplicity**: No additional proxy layer to maintain
2. **Performance**: Direct TLS to pool works well
3. **Algorithm-specific**: CR29 is GPU-specific, doesn't need failover
4. **xmrig-proxy limitation**: Designed for RandomX (CPU) only

### Future: Multi-Algorithm GPU Proxy (RESERVED)
The Python `mining-proxy` module is reserved for future scenarios:
- Multi-algorithm switching (CR29, other algorithms)
- Centralized GPU hashrate aggregation
- Pool failover for GPU workloads

**To enable**: Fix `sha256` in `modules/mining/mining-proxy.nix` and configure `services.mining-proxy`

---

## 🔧 GPU Mining Proxy (ARCHIVED - Reference Only)

### Option A: Use mining-proxy (Python-based)
For multi-algorithm support (CR29 for GPUs):

**Deploy on Forge:**
```nix
services.mining-proxy = {
  enable = true;

  pools = [
    {
      name = "kryptex-cr29-primary";
      url = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
      priority = 1;
      weight = 100;
    }
    # Add failover pools...
  ];

  workers = [
    {
      id = "forge-nvidia-gpu0";
      password = "x";
    }
    # Add other GPUs...
  ];

  listenPort = 3334;  # Different port to avoid conflict
  apiPort = 8082;
};
```

### Option B: Custom Go Proxy
- Build on top of bminer-proxy
- Add CR29 support
- GPU-specific optimizations

---

## 📊 Monitoring Integration

### Prometheus Metrics
The proxy exposes metrics at `http://10.1.1.110:8081/1/summary`

**Add to scrape configs:**
```yaml
- job_name: 'xmrig-proxy'
  static_configs:
    - targets: ['10.1.1.110:8081']
  metrics_path: '/1/summary'
```

---

## ⚠️ Rollback Procedure

If proxy fails, miners can reconnect directly:

```bash
# Stop proxy
ssh zephyr 'sudo systemctl stop xmrig-proxy'

# Miners will failover to direct connection if configured
# Or rebuild with direct pool URLs
```

---

## 📈 Implementation Status

| Task | Status | Notes |
|------|--------|-------|
| xmrig-proxy deployed | ✅ Complete | Running on Zephyr as systemd service |
| Zephyr CPU via proxy | ✅ Complete | 16 threads, zephyr-cpu worker |
| Nexus CPU via proxy | ✅ Complete | 12 threads, nexus-cpu worker |
| Sentry CPU via proxy | ✅ Complete | 8 threads, sentry-cpu worker |
| Nexus GPU conflict | ✅ Resolved | Stopped user-launched duplicate lolMiner |
| TLS option added | ✅ Complete | `tls = false` for proxy connections |
| Pool failover | ✅ Complete | Kryptex (primary) → F2Pool (backup) |
| GPU proxy module | ⏸️ Reserved | mining-proxy.nix for future multi-algo |

### Benefits Realized
- ✅ Single TLS connection to pool (vs 4 separate connections)
- ✅ Centralized hashrate aggregation (~60 kH/s combined)
- ✅ Easy pool switching for testing
- ✅ Per-worker metrics and tracking
- ✅ Automatic pool failover operational

### Optional Enhancements
- ⏳ Integrate with Prometheus dashboards
- ⏳ Add alerting for proxy downtime
- ⏳ Implement GPU proxy for multi-algorithm scenarios

---

## 📈 Next Steps (ARCHIVED)

1. ✅ xmrig-proxy deployed on Zephyr
2. ✅ Test with one CPU miner first
3. ✅ Migrate remaining CPU miners
4. ⏸️ Deploy GPU proxy (mining-proxy or custom)
5. ✅ Add pool failover logic
6. ⏳ Integrate with Prometheus dashboards

---

## 🎯 Benefits

**Immediate:**
- ✅ Single TLS connection to pool (vs 3 separate connections)
- ✅ Centralized hashrate aggregation
- ✅ Easy pool switching for testing

**After Full Migration:**
- Per-worker metrics and tracking
- Automatic pool failover
- Reduced network overhead
- Better observability
