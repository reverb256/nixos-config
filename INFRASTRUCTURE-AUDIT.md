# Infrastructure Audit — 2026-04-15 (Final Update)

## Cluster Overview

| Host | CPU | RAM (used/total) | GPUs | Disk | Load |
|------|-----|-------------------|------|------|------|
| **Zephyr** | 16c | 19GB/31GB | RTX 3060 Ti + RTX 3090 | 88% | 21.5 |
| **Nexus** | 24c | ~20GB/46GB | RTX 3060 Ti @100% | 37% | 6.0 |
| **Forge** | 6c | 10GB/15GB | 2× RX 5700 XT + 2× RTX 4060 | 81% | 4.7 |
| **Sentry** | 16c | ~15GB/31GB | RX 5600 XT | 74% | 11.2 |

---

## K3s Cluster — ALL HEALTHY ✅

| Node | Status | Role |
|------|--------|------|
| zephyr | ✅ Ready | control-plane, etcd |
| nexus | ✅ Ready | control-plane, etcd |
| forge | ✅ Ready | agent |
| sentry | ✅ Ready | control-plane, etcd |

**34 pods running across 16 namespaces. Zero non-running pods.**

---

## Phase Completion Summary (2026-04-15)

### Phase 1: Model Benchmarks ✅
Benchmarked 8 GGUF models on RTX 3090 (24GB VRAM):

| Model | Size | PP128 | TG32 | Notes |
|-------|------|-------|------|-------|
| Qwen3.5-2B Distilled | 1.3G | 6,848 | 252 | Fastest |
| Qwen3.5-4B Distilled | 2.6G | 3,833 | 142 | |
| gemma-4-E2B | 3.2G | 4,887 | 200 | Best prefill |
| gemma-4-E4B | 5.0G | 3,423 | 126 | |
| Qwen3.5-9B Distilled | 5.3G | 2,793 | 99 | |
| **gemma-4-26B-A4B** | **15.6G** | **1,682** | **127** | **★ Best value** |
| Qwen3.5-27B Distilled | 15.4G | 1,009 | 35 | Slow gen |
| gemma-4-31B | 17.4G | 974 | 32 | Slow gen |

**Winner**: gemma-4-26B-A4B — MoE (4B active/26B total), 127 tok/s gen, fits in 24GB VRAM.

### Phase 2: AI Inference Gateway ✅
- Re-enabled on zephyr (then moved to nexus in Phase 5)
- Gateway healthy, connected to llama-server on port 1235
- Routes: local inference + Z.AI fallback + Pollinations fallback

### Phase 3: Multi-Model GPU Serving ✅
- Upgraded zephyr llama-server from gemma-4-E4B → gemma-4-26B-A4B
- RTX 3090: 20.5GB VRAM used, ~4GB free for KV cache
- Same generation speed (127 tok/s) with 5× more parameters (MoE)
- Fixed CUDA_VISIBLE_DEVICES mapping (device 0 = RTX 3090 in container)

### Phase 4: Skipped (another agent working on Hermes Subconscious)

### Phase 5: Wave 1 — Free Zephyr RAM ✅
- Disabled AI inference gateway on zephyr (saves ~140MB RAM)
- Nexus gateway already configured → points to zephyr:1235 for inference
- Single gateway endpoint: nexus:8080 → zephyr:1235 (llama-server)

### Phase 6: Wave 2 — Consolidate Observability ✅
- Disabled on sentry: Prometheus, Grafana, Alertmanager, Loki, Alert-webhook
- Disabled NixOS llamafile on sentry (port conflict with K8s pod)
- Exporters remain active: node-exporter, AMD GPU exporter, mining exporter
- **Nexus is now the single observability hub**

---

## Current Service Distribution

| Service | Zephyr | Nexus | Forge | Sentry |
|---------|--------|-------|-------|--------|
| K3s | server | server | agent | server |
| llama-server (K8s) | ✅ gemma-4-26B | — | — | ✅ gemma-4-E2B |
| AI Gateway | — | ✅ → zephyr:1235 | — | — |
| Prometheus | — | ✅ | — | — |
| Grafana | — | ✅ | — | — |
| Hermes Agent | — | ✅ | — | — |
| Hermes Dashboard | — | ✅ | — | — |
| Caddy HTTPS | ✅ | — | — | — |
| NFS Server | ✅ | — | — | — |
| Vaultwarden | ✅ | — | — | — |
| Redis | ✅ | ✅ | — | — |
| node-exporter | ✅ | ✅ | ✅ | ✅ |
| NVIDIA GPU exporter | ✅ | ✅ | ✅ | — |
| AMD GPU exporter | — | — | ✅ | ✅ |
| Mining exporter | ✅ | ✅ | ✅ | ✅ |

---

## Remaining Issues

### P0
- 🔴 Zephyr disk 88% — needs audit/cleanup
- 🔴 Forge disk 81% — needs audit/cleanup
- 🔴 Zephyr load 21.5 — mining + desktop + control plane

### P1
- 🟡 Prometheus scrape targets need verification
- 🟡 No alerting rules configured
- 🟡 brain_query timeout issues

### P2
- 🟠 llama-server on 0.0.0.0 (should be LAN-only)
- 🟠 etcd ports open on LAN
- 🟠 fail2ban missing on nexus/sentry

### Next Steps
1. Build pi-mcp-server for Hermes↔Pi integration
2. Add alerting rules to nexus Prometheus
3. Security hardening (bind services, fail2ban)
4. Forge disk cleanup
5. Zephyr disk cleanup
