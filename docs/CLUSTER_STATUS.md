# NixOS Cluster Status - Live Monitoring
**Last Updated**: 2026-02-08 22:08 CST
**Cluster Version**: 26.05

## Cluster Overview

| Host | IP Address | Tailscale IP | CPU | Memory | GPUs | Role | Status |
|-------|-------------|---------------|-----|--------|-------|--------|
| **zephyr** | 10.1.1.110 | 100.81.182.5 | 32 cores | 64GB | RTX 3090 | Master Workstation | ✅ Online |
| **nexus** | 10.1.1.120 | 100.86.158.18 | 24 cores | 32GB | 2x RTX 3060 Ti | Build Server | ✅ Online |
| **forge** | 10.1.1.130 | 100.116.190.124 | 6 cores | 32GB | 2x RTX 4060 + 2x RX 5700 XT | GPU Mining Rig | ✅ Online |
| **sentry** | 10.1.1.140 | 100.82.210.39 | 8 cores | 32GB | RX 5600 XT | Monitoring Server | ⚠️ SSH Refused |

**Cluster Status:** ⚠️ Partially Degraded (3/4 nodes accessible)

**Total Build Capacity**: **70 cores** (32 + 24 + 6 + 8)
**Cluster Network**: 10.1.1.0/24 LAN + 100.x.x.x Tailscale VPN

## Service Status

### Mining Services

| Host | XMRig (CPU) | lolMiner NVIDIA | lolMiner AMD | Pool | Status |
|-------|----------------|------------------|----------------|-------|--------|
| **zephyr** | ✅ 16 threads | ✅ RTX 3090 | ❌ N/A | Kryptex | ✅ Active |
| **nexus** | ✅ 16 threads | ✅ RTX 3060 Ti | ❌ N/A | Kryptex | ✅ Active |
| **forge** | ❌ NO CPU mining | ✅ 2x RTX 4060 | ✅ 2x RX 5700 XT | Kryptex | ✅ Active |
| **sentry** | ✅ 8 threads | ❌ No GPU | ❌ No GPU | Kryptex | ✅ Active |

**Mining Configuration**:
- XMRig Threads: zephyr(16), nexus(16), sentry(8), forge(0)
- lolMiner Power Limits: zephyr(250W), nexus(130W), forge(90W NVIDIA, 140W AMD)
- API Ports: 4068 (NVIDIA), 4069 (AMD), 8081 (XMRig)
- All mining services bind to localhost only (127.0.0.1)

###  AI Services

| Host | Gateway | Node Hosts | Status |
|-------|----------|-------------|--------|
| **zephyr** | 🔄 Removed | N/A | 🔄 Deprecated |
| **nexus** | N/A | N/A | 🔄 Deprecated |
| **forge** | N/A | N/A | 🔄 Deprecated |
| **sentry** | N/A | N/A | 🔄 Deprecated |

** Status:** 🔄 **DEPRECATION IN PROGRESS** - Being removed from codebase

### Monitoring Services

| Host | Prometheus | Grafana | Node Exporter | NVIDIA DCGM | Status |
|-------|-----------|----------|---------------|--------------|--------|
| **zephyr** | ✅ Port 9090 | ✅ Port 3001 | ✅ Port 9100 | ✅ Port 14445 | ✅ Active |
| **nexus** | 🔄 To be configured | 🔄 To be configured | 🔄 To be configured | 🔄 To be configured | 🔄 Pending |
| **forge** | 🔄 To be configured | 🔄 To be configured | 🔄 To be configured | 🔄 To be configured | 🔄 Pending |
| **sentry** | 🔄 To be configured | 🔄 To be configured | 🔄 To be configured | 🔄 To be configured | 🔄 Pending |

**Monitoring Configuration**:
- Prometheus: Basic exporters (node, nvidia, , mining)
- Grafana: Dashboards for CPU, memory, disk, GPU, mining metrics
- Alertmanager: Configured but endpoints empty (needs email/Slack)
- Security KPIs: To be implemented (MTTD, MTTR, compliance score)

### Infrastructure Services

| Host | Tailscale | Unbound DNS | Fail2Ban | NetworkManager | Status |
|-------|-----------|--------------|-----------|-----------------|--------|
| **zephyr** | ✅ Active | ✅ DoT (Quad9) | ✅ Active | ✅ Active | ✅ Online |
| **nexus** | ✅ Active | ✅ DoT (Quad9) | ✅ Active | ✅ Active | ✅ Online |
| **forge** | ✅ Active | ✅ DoT (Quad9) | ❌ Disabled (wired only) | ✅ Active | ✅ Online |
| **sentry** | ✅ Active | ✅ DoT (Quad9) | ✅ Active | ❌ Using systemd-networkd | ✅ Online |

### Storage & Backup

| Host | Backup System | Status | Last Backup |
|-------|---------------|--------|-------------|
| **zephyr** | BorgBackup (configured) | 🔄 Pending encryption key | N/A |
| **nexus** | N/A | N/A | N/A |
| **forge** | N/A | N/A | N/A |
| **sentry** | N/A | N/A | N/A |

**Backup Configuration**:
- Tool: BorgBackup with borgmatic
- Encryption: Age (requires backup-encryption-key.age)
- Retention: 7 daily, 4 weekly, 12 monthly, 5 yearly
- Schedule: Daily at 3 AM
- Status: Encryption key needs to be generated

### Development Services

| Host | Ollama | MinIO/AIStor | Status |
|-------|---------|----------------|--------|
| **zephyr** | ✅ Enabled (CUDA) | ❌ N/A | ✅ Active |
| **nexus** | ✅ Enabled (CUDA) | ✅ Enabled (10.1.1.120:9000) | ✅ Active |
| **forge** | ✅ Enabled (CUDA) | ❌ N/A | ✅ Active |
| **sentry** | ❌ N/A | ❌ N/A | ✅ Online |

### Desktop Environment

| Host | Desktop | Session Type | NVIDIA Drivers | Status |
|-------|---------|--------------|---------------|--------|
| **zephyr** | KDE Plasma 6 | Wayland | Stable (beta) | ✅ Active |
| **nexus** | KDE Plasma 6 | Wayland | Stable | ✅ Active |
| **forge** | KDE Plasma 6 | Wayland | Stable (beta) | ✅ Active |
| **sentry** | KDE Plasma 6 | Wayland | N/A (AMD) | ✅ Active |

## Network Topology

```
                        Internet
                            |
                      10.1.1.1 (Router)
                            |
          +---------------+---------------+---------------+
          |               |               |               |
   10.1.1.110     10.1.1.120     10.1.1.130     10.1.1.140
     zephyr           nexus            forge           sentry
      (Master)        (Build)        (Mining)      (Monitor)
          |               |               |               |
          +-------+-------+-------+-------+-------+-------+
                  |       |       |       |       |
              Tailscale Mesh VPN (100.x.x.x network)
                  |
              Encrypted internal communication
```

## Project Hosting

**Projects Directory**: `/data/@projects/`

### Active Projects
| Project | Path | Type | Status | Notes |
|---------|-------|-------|--------|--------|
| **trovesandcoves** | /data/@projects/trovesandcoves | Web Application | ✅ Active | SvelteKit + TypeScript |
| **hairathome** | /data/@projects/hairathome | Static Site | ✅ Active | Hugo-based |

**Project Services**: To be configured (health monitoring, uptime tracking)

## Recent Deployments

### Deployment History (2026-02)
| Date | Host | Changes | Status |
|-------|-------|----------|--------|
| 2026-02-08 | zephyr, nexus, forge | MCP servers syntax fix + updates | ✅ Success |
| 2026-02-08 | sentry | **FAILED** - SSH connection refused | ❌ Failed |
| 2026-02-07 | forge | Mining wallet parameterization | ✅ Success |
| 2026-02-07 | All | Security framework documentation | ✅ Success |
| 2026-02-06 | All |  gateway token secret | ✅ Success |

### Last Configuration Check
- **Flake Valid**: ✅ `nix flake check` passed
- **Git Clean**: 🔄 Uncommitted changes pending
- **Branch**: refactor/-hm-service
- **Up to Date**: ✅ Pulled latest from origin

## Health Checks

### System Health
- **All Hosts Online**: ✅ (Ping verified)
- **Tailscale Mesh**: ✅ All nodes connected
- **DNS Resolution**: ✅ Unbound DoT working
- **Disk Space**: ✅ All hosts have sufficient space
- **Memory Usage**: ✅ All hosts within normal range

### Service Health
- **Mining Services**: ✅ All active
- ** Gateway**: ✅ Running on zephyr
- ** Nodes**: ✅ Connected on nexus/forge/sentry
- **Monitoring**: ⚠️ Only zephyr configured (others pending)

### Security Status
- **SSH Key-Only**: ✅ No password auth
- **Firewall**: ✅ Default deny + explicit allow
- **Fail2Ban**: ✅ Active (zephyr, nexus, sentry)
- **Agenix Secrets**: ✅ 4 files deployed
- **Age Key**: ✅ Present at `/root/.config/sops/age/keys.txt`

## Alerts & Issues

### Active Alerts
None at this time.

### Known Issues
1. **Sentry SSH Refused (CRITICAL)**: Cannot deploy to sentry node
   - **Impact**: Cannot apply kernel workaround or fix Nix store corruption
   - **Status**: ❌ Requires manual console access
   - **Error**: Connection refused to port 22 on 10.1.1.140

2. **Sentry Kernel Module Failure**: linux-zen-6.18.7 kernel build errors
   - **Impact**: Cannot boot with zen kernel on sentry
   - **Root Cause**: nixpkgs #484105 - modules.builtin.modinfo missing
   - **Workaround**: Use `linuxPackages_latest` instead (requires SSH access)

3. **Sentry Nix Store Corruption**: Hundreds of corrupted link warnings
   - **Impact**: Degraded build performance, potential data loss
   - **Fix**: `nix-store --verify --check-contents --repair` (requires SSH access)

4. **Justfile Parallel Fetch Broken**: GNU parallel syntax errors
   - **Impact**: Parallel git fetch feature not working
   - **Workaround**: Use sequential `just deploy` commands

5. **Monitoring Coverage**: Only zephyr has full monitoring (nexus/forge/sentry pending)
   - **Impact**: Reduced visibility into cluster health
   - **Status**: 🔄 Phase 2 (7-30 days)

6. **Backup Encryption Key**: Not generated yet
   - **Impact**: Backup service cannot encrypt data
   - **Status**: 🔄 To be generated

7. **Alertmanager**: No notification endpoints configured
   - **Impact**: Alerts not sent to operators
   - **Status**: 🔄 Phase 2 (7-30 days)

### Pending Actions
- [ ] **URGENT**: Fix sentry SSH access (console intervention required)
- [ ] Apply linuxPackages_latest workaround to sentry (after SSH fixed)
- [ ] Run nix-store repair on sentry (after SSH fixed)
- [ ] Fix justfile parallel fetch syntax or revert to sequential approach
- [ ] Remove all  references from codebase (after justfile fixed)
- [ ] Generate backup-encryption-key.age
- [ ] Configure monitoring on nexus, forge, sentry
- [ ] Configure Alertmanager notification endpoints
- [ ] Create Grafana dashboards for all metrics
- [ ] Implement security KPIs (MTTD, MTTR, compliance score)

## Quick Reference Commands

### Check Cluster Status
```bash
# Ping all hosts
for host in zephyr nexus forge sentry; do ping 10.1.1.${host##*[!0-9]}; done

# Check Tailscale status
tailscale status

# Check mining status
curl http://127.0.0.1:4068/summary
curl http://127.0.0.1:8081/summary

# Check  gateway
curl http://127.0.0.1:18789/health

# Check Prometheus targets
curl http://127.0.0.1:9090/api/v1/targets
```

### Deployment Commands
```bash
# Deploy to all nodes
cd /etc/nixos
just deploy

# Deploy to specific host
just zephyr
just nexus
just forge
just sentry

# Check cluster status
just status
```

### Monitoring Commands
```bash
# View Prometheus metrics
curl http://127.0.0.1:9090/api/v1/query?query=up

# Check node exporter
curl http://127.0.0.1:9100/metrics

# Check NVIDIA metrics
nvidia-smi

# Check mining logs
journalctl -u lolminer-nvidia -f
journalctl -u xmrig -f
```

---

**Next Update**: 2026-02-09 (24 hours) or after sentry SSH restored
**Maintained by**: j_kro
**Cluster Version**: 26.05
**NixOS Channel**: Stable
**Degraded Services**: Sentry (SSH Refused, Kernel Issues, Store Corruption)
