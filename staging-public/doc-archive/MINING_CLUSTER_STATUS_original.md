# Mining Cluster Configuration & Performance

## Cluster Overview

**Status:** 3/4 nodes operational (75%)
**Total Performance:** ~25 kH/s CPU + ~25 g/s GPU mining
**Mining Pool:** Kryptex Network (SSL/TLS encrypted)

## Active Nodes

### 🌟 Zephyr (192.168.100.X) - Master Workstation
- **Hardware:** Ryzen 5950X (16 cores) + RTX 3090
- **Services:**
  - ✅ NVIDIA GPU Mining (RTX 3090)
  - ✅ CPU Mining (Ryzen 5950X)
- **Status:** Fully operational

### 🔧 Nexus (192.168.100.X) - Build Node
- **Hardware:** Ryzen 3900X (12 cores) + 2x RTX 3060 Ti
- **Services:**
  - ✅ NVIDIA GPU Mining (RTX 3060 Ti)
  - ✅ CPU Mining (Ryzen 3900X)
- **Status:** Fully operational

### 👁️ Sentry (192.168.100.X) - Monitoring Node
- **Hardware:** Ryzen 1700 (8 cores)
- **Services:**
  - ✅ CPU Mining (Ryzen 1700)
- **Status:** Fully operational

### 🔥 Forge (192.168.100.X) - GPU Mining Rig
- **Hardware:** 2x RTX 4060 + 2x RX 5700 XT
- **Services:**
  - ❌ NVIDIA GPU Mining (RTX 4060) - Network unreachable
  - ❌ AMD GPU Mining (RX 5700 XT) - Network unreachable
- **Status:** Network configuration issue
- **ROCm Status:** ROCm 6.x configured but untested

## Configuration Details

### Mining Services
- **CPU Mining:** XMRig with optimized thread allocation
- **NVIDIA Mining:** lolMiner with CUDA acceleration
- **AMD Mining:** lolMiner with ROCm 6.x (configured but untested)

### Pool Configuration
- **Primary:** `xtm-rx-us.kryptex.network:8038` (XMRig CPU)
- **Secondary:** `xtm-c29-us.kryptex.network:8040` (lolMiner GPU)
- **SSL/TLS:** All connections encrypted
- **Wallet:** `WALLET_PREFIX.NODE_NAME{hostname}` (per-node identification)

### Monitoring
- **Script:** `./mining-monitor.sh`
- **Checks:** Service status, API hashrates, network connectivity
- **Frequency:** Manual execution (can be automated with cron)

## Issues & Next Steps

### Critical Issues
1. **Forge Network Connectivity**
   - NetworkManager configuration conflict
   - IP: 192.168.100.X unreachable
   - Requires physical/console access to repair

2. **AMD GPU Mining**
   - ROCm 6.x configured but untested
   - May require additional driver/kernel compatibility work

### Performance Optimization
1. **GPU Hashrate APIs** - Currently returning null values
2. **CPU Thread Optimization** - Fine-tune based on real-world performance
3. **Power Management** - Add thermal/power monitoring

### Future Enhancements
1. **Automated Monitoring** - Cron jobs for regular status checks
2. **Alert System** - Email/notifications for service failures
3. **Performance Dashboard** - Web interface for real-time stats
4. **Profitability Tracking** - Integration with mining calculators

## Commands

### Monitoring
```bash
./mining-monitor.sh  # Check all cluster services
```

### Service Management
```bash
# Check specific service
ssh {host} systemctl status {service}

# Restart service
ssh {host} sudo systemctl restart {service}

# View logs
ssh {host} journalctl -u {service} -f
```

### Deployment
```bash
# Deploy to all nodes
colmena apply

# Deploy to specific node
colmena apply --on {hostname}

# Test configuration
nixos-rebuild test --flake .#{hostname}
```

## Security Notes
- All mining traffic encrypted with SSL/TLS
- Services run under dedicated mining user accounts
- Network firewall restricts mining API access to localhost
- Analytics/telemetry blocking active for privacy