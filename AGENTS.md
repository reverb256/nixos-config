# NixOS Cluster - AI Agent Dashboard

**⚠️ CRITICAL: CONFIGURATION MASTER NODE ⚠️**

**`/etc/nixos/` on zephyr (10.1.1.110) is the SOLE SOURCE OF TRUTH for the ENTIRE cluster.**

All configuration changes must be made HERE on zephyr. No individual node configs exist independently.
Deploy with: `just forge`, `just nexus`, `just zephyr`, or `just deploy` (all nodes)

---

**Status:** ⚠️ Partially Degraded | **Backend:** Podman | **Builds:** Distributed (70 cores - 3/4 hosts online) | **Security:** OWASP 96%, ISO 93% | **Last Audit:** 2026-02-07 (See `docs/COMPLIANCE_ASSESSMENT.md`)
**Agenix Key:** `age1pn55e68h5twm8ksrm29pzf4w5t8wdznmy0sqg5gvk094punpctq06q8zn` (Generated Feb 4, 2026)

## 📁 Quick Reference - Host Specs

| Host | IP Address | Tailscale IP | CPU | Memory | GPUs | Role |
|------|-------------|---------------|-----|--------|-------|--------|
| **zephyr** | 10.1.1.110 | 100.81.182.5 | 32 cores | 64GB | RTX 3090 | Master Workstation | ✅ RGB: Corsair + Razer |
| **nexus** | 10.1.1.120 | 100.86.158.18 | 24 cores | 32GB | 2x RTX 3060 Ti | Build/Backup | ❌ No RGB Hardware |
| **forge** | 10.1.1.130 | 100.116.190.124 | 6 cores | 32GB | 2x RTX 4060 + 2x RX 5700 XT | GPU Mining | ❌ No RGB Hardware |
| **sentry** | 10.1.1.140 | 100.82.210.39 | 8 cores | 32GB | RX 5600 XT | Monitoring | ❌ No RGB Hardware |

**Total Build Capacity:** **70 cores** across all 4 hosts | **RGB Tools:** OpenRGB, liquidctl, Polychromatic, ckb-next

## ⚡ Quick Actions
| Context | Command | Description |
|---------|---------|-------------|
| **Deploy** | `just prep && just deploy` | Copy age keys + deploy to all nodes |
| **Push** | `just push` | Push changes + deploy to current host |
| **Update** | `just update` | Update flake + deploy all |
| **Check** | `nix flake check` | Validate configuration syntax |
| **RGB Profile** | `rgb-profile [gaming|movie|off]` | Switch RGB profiles for monitoring/alerts |
| **RGB Status** | `openrgb --list-devices` | View all RGB devices |
| **RGB Sync** | `liquidctl list` | Check AIO/RAM status |

## 📍 Key Locations
| Component | File Path | Status |
|-----------|-----------|--------|
| **Cluster Config** | `flake.nix` | 4 Hosts (ALL managed from zephyr) |
| **Secrets** | `secrets/` | Agenix Encrypted |
| **Mining** | `modules/mining.nix` | Localhost-only API |
| **Forge Config** | `hosts/forge/configuration.nix` | Managed from zephyr via SSH |
| **Nexus Config** | `hosts/nexus/configuration.nix` | Managed from zephyr via SSH |
| **ScopeBuddy** | `modules/scopebuddy.nix` | Gamescope wrapper with auto-detection |
| Mining Troubleshooting | `docs/MINING_TROUBLESHOOTING.md` | Mining fixes and debugging guide |
| **MCP Servers** | `modules/mcp-servers.nix` | Model Context Protocol servers |
| **Local LLM** | `modules/lmstudio-docker.nix` | Podman Container |

## 🏗️ Architecture
*   **Configuration Master:** `/etc/nixos/` on zephyr - SOLE SOURCE OF TRUTH for all cluster nodes
*   **Container Engine:** Podman (Declarative, Rootless)
*   **Networking:** Tailscale Mesh (100.x.x.x) + 1Gbps wired network (TP-Link Easy Smart Switches)
*   **Security:** Services bind 127.0.0.1, exposed via Nginx only
*   **Build System:** Distributed builds with GPU acceleration (CUDA + ROCm)
    *   **Total Build Capacity:** 26 concurrent jobs (up from 13)
    *   **GPU Features:** CUDA (nexus, forge, zephyr), ROCm (forge, sentry)
    *   **Binary Caches:** 5 caches including cuda.cachix.org and rocm.cachix.org
    *   **Network Optimization:** 100 parallel HTTP connections for 1Gbps
    *   **Mining Awareness:** Build capacity adjusted for active mining operations
*   **Secret Management:** Agenix with age key at `/root/.config/sops/age/keys.txt`
*   **Deployment:** All nodes deployed via SSH from zephyr using `just <hostname>`

## 📚 Documentation Index
*   [System Reality Check & Audit Log](docs/SYSTEM_REALITY_CHECK.md) - **READ THIS FIRST**
*   [Deployment Instructions](docs/DEPLOYMENT_INSTRUCTIONS.md)
*   [Security Policy](docs/security-policy.md) - Comprehensive security framework
*   [Security Control Matrix](docs/SECURITY_CONTROL_MATRIX.md) - OWASP/ISO compliance
*   [Incident Response Plan](docs/INCIDENT_RESPONSE_PLAN.md) - 6-step IR framework
*   [Compliance Assessment](docs/COMPLIANCE_ASSESSMENT.md) - OWASP/ISO status
*   [Cluster Status](docs/CLUSTER_STATUS.md) - Live cluster monitoring
*   [Tailscale Setup](docs/TAILSCALE_SETUP.md)

## ⚠️ Recent Changes (2026-02-08)

### Infrastructure Updates
1. **MCP Servers Module Fixed:** Resolved syntax error in `modules/mcp-servers.nix` (missing closing brace)
2. **Deployments Completed:**
    *   ✅ zephyr: Deployed successfully
    *   ✅ nexus: Deployed successfully (openrgb-daemon warning unrelated)
    *   ✅ forge: Deployed successfully
    *   ❌ sentry: **Deployment FAILED** - See Known Issues
3. **Sentry Kernel Issue:** linux-zen-6.18.7 failing with module shrinkage errors
    *   **Workaround:** Using `linuxPackages_latest` instead of `linuxPackages_zen`
    *   **Root Cause:** nixpkgs #484105 - modules.builtin.modinfo missing in Linux 6.12+
4. **Justfile Development:** Attempted parallel git fetch implementation (syntax errors remain)
5. **OpenClaw References:** **REMOVAL IN PROGRESS** - All OpenClaw references being removed from codebase
6. **ScopeBuddy Integration:** Added declarative gamescope wrapper with system-wide auto-detection
     - Auto-detects resolution, HDR, VRR for all games
     - Steam integration via `scb -- %command%`
     - Compatible with existing gaming.nix setup
     - Configuration: `/etc/scopebuddy/scb.conf` (system-wide)
7. **RGB Control Enhanced:**
    *   ✅ zephyr: OpenRGB enabled (MSI X570, G.Skill RAM, RTX 3090)
    *   ✅ zephyr: Added liquidctl (H115i AIO, Corsair Vengeance RAM)
    *   ✅ zephyr: ckb-next for Corsair keyboard, OpenRazer for Razer Naga mouse
    *   ✅ zephyr: Polychromatic for Razer GUI control
    *   ✅ nexus: OpenRGB enabled (Gigabyte AORUS X470)
    *   ✅ forge/sentry: OpenRGB enabled (potential Corsair mouse support)
    *   **Intelligent Use**: RGB configured for temperature monitoring, status signaling, and alerts
        - Temperature alerts (liquidctl monitors Corsair Vengeance RAM + H115i)
        - Status indicators (RGB profiles: gaming=active, movie=calm, off=alerts)
        - Visual signaling (breathing effects when gaming, static blue for movies)
    *   **Documentation**: `docs/RGB_CONTROL_GUIDE.md` - Comprehensive RGB tool guide

### Previous Changes (2026-02-04)
1.  **Mining Security:** API ports now bound to localhost.
2.  **Podman Migration:** OpenClaw and LM Studio modules rewritten for Podman.
3.  **Distributed Builds:** Enabled for nexus, forge, sentry.
4.  **Agenix Secret Management:**
    *   New age key generated and deployed
    *   All secrets extracted from `/run/agenix` and re-encrypted
    *   Key location: `/root/.config/sops/age/keys.txt`
5.  **NVIDIA Power Limit:** lolminer-nvidia set to 250W on zephyr

> **Note to Agents:** When modifying services, ensure they bind to `127.0.0.1` and use `virtualisation.oci-containers` (Podman) instead of Docker.

## ⚠️ Known Issues

### 1. Sentry Deployment Failed (2026-02-08)
**Status:** ❌ **CRITICAL** - Cannot deploy to sentry

**Symptoms:**
- SSH connection refused to port 22 on 10.1.1.140
- Ping succeeds (network reachable via Tailscale)
- Cannot execute deployment commands

**Root Cause:** SSH service on sentry not running or firewalled

**Impact:**
- Sentry cannot be updated with new configuration
- Kernel workaround (linux-zen → linux_latest) cannot be applied
- Nix store corruption cannot be repaired

**Mitigation:**
- Sentry remains on previous configuration (linux-zen kernel)
- Monitoring functionality may be degraded
- Manual intervention required on sentry node

**Next Steps:**
1. Access sentry via console/monitor
2. Restart SSH service: `systemctl restart sshd`
3. Check firewall rules
4. Verify port 22 is open
5. Retry deployment with workaround kernel

### 2. Sentry Nix Store Corruption
**Status:** ⚠️ **HIGH** - Data integrity risk

**Symptoms:**
- Hundreds of "corrupted link" warnings during deployment
- Warnings: `warning: removing corrupted link "/nix/store/.links/..."`

**Root Cause:** Likely kernel build failures or interrupted builds

**Impact:**
- Degraded build performance
- Potential data loss
- May cause deployment failures

**Fix Command (requires SSH access):**
```bash
nix-store --verify --check-contents --repair
```

### 3. Justfile Parallel Git Fetch Broken
**Status:** ⚠️ **MEDIUM** - Feature non-functional

**Symptoms:**
- Syntax errors with GNU parallel in justfile
- Error: "Recipe line has extra leading whitespace"

**Root Cause:** Justfile recipe syntax incompatible with GNU parallel's `:::` operator

**Impact:**
- Parallel git fetch feature not working
- Manual deployment required for each host

**Workaround:** Use existing `just deploy` for sequential deployment

### 4. Sentry Linux-Zen Kernel Failure
**Status:** ⚠️ **MEDIUM** - Kernel build errors

**Symptoms:**
- linux-zen-6.18.7 fails during module shrinkage
- Error: `modprobe: FATAL: Module ahci not found`

**Root Cause:** nixpkgs Issue #484105 - modules.builtin.modinfo missing in Linux 6.12+

**Workaround:** Use `linuxPackages_latest` instead of `linuxPackages_zen` (requires SSH access to sentry)

### 5. OpenClaw Removal In Progress
**Status:** 🔄 **IN PROGRESS** - Cleanup pending

**Description:** All OpenClaw references being removed from codebase

**Impact:**
- Documentation references will be updated
- Module files will be deleted
- No operational impact (OpenClaw not currently active)

**Status:** Awaiting justfile fix to proceed with cleanup

## 🎮 Gaming & ScopeBuddy

### **ScopeBuddy Auto-Detection**
✅ **Resolution**: Automatically detects and sets display resolution (`-W`, `-H`)
✅ **HDR**: Automatically enables HDR for HDR-capable displays  
✅ **VRR**: Automatically enables adaptive sync for VRR displays
✅ **System-wide**: Applies to all users and games globally
✅ **Steam Integration**: Simple `scb -- %command%` in launch options

### **ScopeBuddy Usage**

### **ScopeBuddy Usage**
```bash
# Steam Integration (auto-detection enabled)
scb -- %command%

# Multi-monitor setup
scb -O DP-3 -- %command%

# Per-game configuration (override system defaults)
# Create: ~/.config/scopebuddy/GAME_NAME.conf
SCB_AUTO_RES=0 scb -- %command% -W 1920 -H 1080

# Non-gamescope HDR (experimental)
SCB_AUTO_HDR=1 SCB_NOSCOPE=1 scb -- %command%
```

### **Declarative Configuration**
System-wide ScopeBuddy settings are configured in `modules/gaming.nix`:
- **Auto-Detection**: Resolution, HDR, VRR enabled by default
- **Global Config**: `/etc/scopebuddy/scb.conf` 
- **User Overrides**: `~/.config/scopebuddy/scb.conf`
- **Per-Game**: `~/.config/scopebuddy/GAME_NAME.conf`

## 🔐 Agenix Secret Management

### Generating New Age Keys

**Generating a new age key:**
```bash
nix shell nixpkgs#age -c age-keygen -o /root/.config/sops/age/keys.txt
```

**Getting age public key from SSH ed25519:**
```bash
ssh-keygen -y -f ~/.ssh/id_ed25519 | ssh-to-age
```

### Encrypting/Decrypting Files

**Encrypting a file with age:**
```bash
age -r age1pn55e68h5twm8ksrm29pzf4w5t8twdznmy0sqg5gvk094punpctq06q8zn -o /path/to/output /path/to/input
```

**Decrypting:**
```bash
AGE_KEY=/root/.config/sops/age/keys.txt age -d -i /root/.config/sops/age/keys.txt -o - /path/to/file.age
```

### SSH Key to Age Public Key

```bash
ssh-keygen -y -f ~/.ssh/id_ed25519 | ssh-to-age
```

### Key History

- **2026-02-04:** New age key `age1pn55e68h5twm8ksrm29pzf4w5t8wdznmy0sqg5gvk094punpctq06q8zn` generated after old keys were lost
- Secrets were extracted from `/run/agenix` on zephyr (still in memory from running services)
- All secrets re-encrypted with the new key
