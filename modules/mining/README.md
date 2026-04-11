# Mining Modules

Mining modules manage cryptocurrency mining for the cluster, covering CPU mining
(XMRig/RandomX), GPU mining (lolMiner/CR29), proxy infrastructure, and desktop
integration. All mining is coordinated centrally via proxies on Zephyr and Forge.

## Module Inventory

| Module | Purpose | Used By |
|--------|---------|---------|
| `mining.nix` | Core mining config: lolMiner (NVIDIA/AMD), XMRig CPU, GPU power limits | All mining hosts |
| `dual-xmrig.nix` | Two XMRig instances: always-on + flexible (pause during gaming) | Zephyr, Nexus |
| `xmrig-proxy.nix` | CPU mining stratum proxy (RandomX pool aggregation) | Zephyr |
| `gpu-proxy-cpp.nix` | C++ GPU mining stratum proxy (CR29/Kryptex) | Forge |
| `mining-proxy.nix` | Python universal stratum proxy (reserved/incomplete) | Unused |
| `mining-desktop-toggle.nix` | KDE Plasma desktop icon for toggling K8s GPU miner | Zephyr |
| `mining-plasmoid.nix` | Plasma 6 widget showing multi-node mining metrics | Zephyr |

## Mining Proxy Topology

```
                    ┌─────────────────────────────────────┐
                    │          Kryptex Pool(s)             │
                    │  (xtm-rx-us/eu, xtm-c29-us/eu)      │
                    └──────┬──────────────────┬────────────┘
                           │                  │
                    RandomX (CPU)      CR29 (GPU)
                           │                  │
                ┌──────────▼──────────┐  ┌────▼──────────────────┐
                │  XMRig Proxy        │  │  GPU Proxy C++        │
                │  (Zephyr :3333)     │  │  (Forge :3334)        │
                │  CPU hashrate agg   │  │  GPU hashrate agg     │
                └──────────┬──────────┘  └────┬──────────────────┘
                           │                  │
              ┌────────────┼─────────┐    ┌───┼──────────┐
              │            │         │    │   │          │
         Zephyr-CPU   Nexus-CPU  Sentry-CPU  Zephyr-GPU Nexus-GPU Forge-GPU
         (flexible)   (disabled) (K8s)       (K8s)     (K8s)     (bare-metal)
```

### Proxy Chain

1. **CPU Mining** → Workers connect to XMRig Proxy on Zephyr (`10.1.1.110:3333`)
   - Proxy aggregates hashrate and routes to Kryptex RandomX pools
   - Workers: zephyr-cpu, nexus-cpu, sentry-cpu

2. **GPU Mining** → Workers connect to GPU Proxy C++ on Forge (`10.1.1.130:3334`)
   - Translates CR29 stratum protocol for Kryptex
   - Workers: forge-gpu (bare-metal), zephyr-gpu (K8s), nexus-gpu (K8s)

## Mining Migration Status

| Workload | Status | Location |
|----------|--------|----------|
| Zephyr GPU (RTX 3090) | ✅ K8s | `gpu-miner-zephyr` deployment |
| Nexus GPU (3060 Ti) | ✅ K8s | `gpu-miner-nexus` deployment |
| Forge NVIDIA (2× 4060) | ✅ K8s | `gpu-miner-forge-nvidia-0/1` |
| Forge AMD (2× 5700 XT) | ✅ K8s | `gpu-miner-forge-amd-0/1` |
| Zephyr CPU (flexible) | Bare-metal | `xmrig-flexible` systemd service |
| Nexus CPU | Disabled | K8s deployment scaled to 0 |
| Sentry CPU | Disabled | K8s deployment scaled to 0 |

## Dual XMRig Setup

The `dual-xmrig.nix` module provides two XMRig instances per host:

- **alwaysOn**: Mines even during gaming (low thread count, unintrusive)
- **flexible**: Pauses during gaming/builds (higher thread count, coordinated
  by `gaming-detection` and `mining-coordinator` services)

Both instances connect to the local XMRig proxy for centralized management.

## GPU Power Management

GPU power limits are set at boot via systemd services and persist regardless
of whether mining is active:

| Host | GPU | Power Limit | Method |
|------|-----|-------------|--------|
| Zephyr | RTX 3090 (GPU1) | 250W | `nvidia-gpu-power-limit.service` |
| Zephyr | 3060 Ti (GPU0) | No limit | Reserved for AI/ML |
| Forge | RTX 4060 ×2 | 90W each | `nvidia-gpu-power-limit.service` |
| Forge | RX 5700 XT ×2 | 110W each | `amd-gpu-power-mgmt.service` |
| Nexus | 3060 Ti | 120W | `nvidia-gpu-power-limit.service` |

## Adding a New Mining Host

1. Enable `profiles.role.mining` in the host's node profile
2. Configure `services.mining` in the host's services module:
   - CPU: Set `xmrigDual` or `xmrig` with pool pointing to Zephyr proxy
   - GPU: Configure `lolminer` with pool pointing to Forge proxy
3. Add worker credentials to the proxy config on Zephyr/Forge
4. Open stratum port in the host's firewall module
