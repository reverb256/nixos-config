# Mining Proxy Migration Progress

## Status: Migrating Zephyr CPU Miner (Proof of Concept)

### Step 1: Verify Proxy Status
- ✅ xmrig-proxy running on Zephyr (PID 992956)
- ✅ Stratum port 3333 listening
- ✅ Proxy config: kryptex-rx-test pool
- ⚠️  API only on localhost (127.0.0.1:8081)

### Step 2: Migrate Zephyr CPU Miner
**Current Config:**
- Pool: xtm-rx-us.kryptex.network:8038 (direct)
- User: krxXVNVMM7.zephyr
- Hashrate: ~15-18 KH/s

**New Config:**
- Pool: stratum+tcp://10.1.1.110:3333 (via proxy)
- User: zephyr-cpu (worker ID)
- Expected: Same hashrate, centralized connection

### Step 3: Monitor and Verify
- Check hashrate stability for 10 minutes
- Verify proxy metrics show connected worker
- If hashrate drops >5%, rollback immediately

### Rollback Procedure
```bash
# Stop using proxy
ssh zephyr 'sudo systemctl restart xmrig'

# Verify direct connection restored
ssh zephyr 'sudo cat /run/xmrig/config.json | jq .pools[0].url'
```

### Remaining Migration
After Zephyr successful:
- [ ] Nexus CPU miner (8 threads, krishna-cpu worker)
- [ ] Sentry CPU miner (8 threads, sentry-cpu worker)
- [ ] Verify total hashrate stable
- [ ] Deploy GPU proxy for lolminer

### Proxy Benefits
- ✅ Single TLS connection to pool
- ✅ Easy pool switching
- ✅ Centralized metrics
- ✅ Per-worker tracking
