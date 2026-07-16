# Action Items — Consolidated

> **Last Updated:** 2026-07-15
> **Source:** Cross-session audit of cluster infrastructure, security posture, vLLM containerization, NixOS config.

---

## Priority Key

| Priority | Meaning | Examples |
|----------|---------|---------|
| **P0** | Breaking / high blast radius | secrets in plaintext, GPU starvation, SSH auth |
| **P1** | Immediate ROI / active blocker | NodePort exposure, funnel host command |
| **P2** | Important, needs planning | mTLS, audit policy, runAsNonRoot rollout |
| **P3** | Defensive / nice-to-have | image scanning, SBOMs, model integrity |

---

## Blocked Items (must be unblocked first)

~~| # | Item | Blocked By | Why |~~
~~|---|------|-----------|-----|~~
~~| **B3** | Switch llama-server image to vLLM container | First CI build of `ghcr.io/reverb256/vllm-turboquant:0.20.0` | Image doesn't exist yet. CI build at github.com/reverb256/vllm-turboquant must complete first. |~~

**B3 RESOLVED**: Restored nix-csi scratch container deployment using `vllm-turboquant-env` from `/data/projects/own/vllm`. No OCI image needed - uses host `/nix` store mount.

---

## Critical (P0)

| # | Item | What | Context |
|---|------|------|---------|
| **P0-1** | Etcd encryption at rest + secret rotation | All 72 K8s secrets (Casdoor, Grafana, API keys, DB passwords, OIDC client secrets) are stored in plaintext in etcd. Any node with filesystem access to etcd data dir can read all secrets. | Encryption at rest (`--encryption-provider-config` with aescbc key) needs to be enabled on all 3 etcd members (zephyr, nexus, sentry). After encryption is enabled, every secret must be rotated (delete + recreate) to actually be encrypted. |
| **P0-2** | Enforce runAsNonRoot + drop ALL capabilities | ~30 pods run as root with full capability set. Violates Pod Security Standards (restricted). | Requires per-deployment changes: `securityContext.runAsNonRoot: true`, `securityContext.capabilities.drop: ["ALL"]`. Test incrementally, start with monitoring stack. |
| **P0-3** | Fix nvidia-container-runtime on NixOS | `libnvidia-ml.so.1` dlopen fails due to NixOS glibc LD_LIBRARY_PATH handling. K8s pods cannot isolate GPUs. | Known NixOS issue. Current workaround: `CUDA_VISIBLE_DEVICES` as hint + `mining-inference-coordinator`. Resolution requires NixOS patching or Podman GPU backend. |

---

## High Priority (P1)

| # | Item | What | Context |
|---|------|------|---------|
| **P1-1** | Restrict NodePort access (17 services) | 17 K8s services in `ai-inference` expose NodePorts bypassing Caddy auth. Any 10.x device can reach llama-server, Qdrant, Redis directly. | Options: (a) Firewall NodePort range on all nodes except zephyr; (b) Migrate to ClusterIP; (c) NetworkPolicy source restriction. Option (a) is simplest. |
| **P1-2** | Deploy Falco runtime security | Zero runtime security monitoring. Container breakout has no detection. | Falco DaemonSet with default + custom rules. Start audit-only, no blocking. |

---

## Medium Priority (P2)

| # | Item | What | Context |
|---|------|------|---------|
| **P2-1** | Enable K8s audit policy + log shipping | No audit log. No forensic trail if compromised. | Enable `--audit-policy-file` on K3s API server. Ship to Loki via Alloy. |
| **P2-2** | Enforce Pod Security Standards on all namespaces | Only 2 namespaces have PSS labels. Others allow privileged. | Add PSS labels (enforce=baseline, audit=restricted, warn=restricted) to all namespaces. |
| **P2-3** | Evaluate service mesh for mTLS | Pod-to-pod traffic in plaintext. | Evaluate Istio ambient mesh or Cilium. Scoped as "evaluate only" for now. |
| **P2-4** | Add nvme_core.timeout=30 on nexus boot | NVMe drive can time out on boot. | `boot.kernelParams` addition. |
| ~~**P2-4**~~ | ~~Add nvme_core.timeout=30 on nexus boot~~ | ~~NVMe drive can time out on boot.~~ | **DONE 2026-07-14**: `nvme_core.timeout=30` confirmed already set on nexus boot parameters. |
| ~~**P2-5**~~ | ~~Add Casdoor MCP scopes to mcp-client app~~ | ~~OAuth app missing MCP scopes. Tool calls may fail.~~ | **RESOLVED 2026-07-15**: casdoor MCP bridge removed from registry + hermes-cli (full Path A cleanup). Casdoor is being phased out cluster-wide — oauth2-proxy handles .lan auth. The `casdoor-hermes-jwt` sops secret is retained for transitional back-compat only; will be migrated in a followup. |

---

## Low Priority (P3)

| # | Item | What | Context |
|---|------|------|---------|
| **P3-1** | Image scanning admission controller | No CVE scanning before deploy. | Trivy admission webhook. Block critical CVEs. |
| **P3-2** | Model file integrity verification | GGUF models loaded without SHA-256 check. | Add checksum step to llama-server startup. Store hashes in ConfigMap. |
| **P3-3** | Generate SBOMs for all container images | No software bill of materials. | `docker sbom` or `syft` on each built image. |
| **P3-4** | ai-inference namespace lockdown | Privileged namespace. Tighten after GPU isolation fixed. | Change PSS label to `baseline` after P0-3. |
| ~~**P3-5**~~ | ~~Remove stale NixOS Grafana module~~ | ~~`services.monitoring.grafana` disabled but config exists.~~ | **DONE 2026-07-14**: `grafana-v2.nix` deleted; import line commented out in `modules/services/monitoring/default.nix`. Grafana runs exclusively as K8s deployment. |
| ~~**P3-6**~~ | ~~Clean up stale OIDC K8s secrets~~ | ~~`haven-oidc`, `mission-control-oidc`, `kagent-oidc` never mounted.~~ | **DONE 2026-07-14**: Stale OIDC secrets confirmed already removed. No Nix references remain. |

---

## Project-Specific Items

### Tailscale / Networking

| # | Item | Status |
|---|------|--------|

### vLLM / TurboQuant

| # | Item | Status |
|---|------|--------|
| ✅ V1 | Wait for GHCR CI build of vllm-turboquant:0.20.0 | **RESOLVED** - Using nix-csi instead |
| ✅ V2 | Switch llama-servers.nix to vLLM image | **COMPLETE** - Restored working nix-csi config |
| ✅ V3 | Remove 4 host mounts from llama-servers.nix | **NA** - Not needed with nix-csi approach |

### NixOS Config

| # | Item | Status |
|---|------|--------|
| ✅ N1 | nvme_core.timeout=30 on nexus (P2-4) | **DONE** — confirmed already set |
| ✅ N2 | Delete stale Grafana NixOS module (P3-5) | **DONE** — grafana-v2.nix deleted 2026-07-14 |
| ✅ N3 | Clean up stale OIDC secret K8s defs (P3-6) | **DONE** — confirmed already removed 2026-07-14 |
| ✅ N4 | Deploy `dashboard.lan` (Glance) | **DONE** — Glance deployed, Caddy route wired in nexus/services.nix |

### Model / Provider Config

| # | Item | Status |
|---|------|--------|
| ~~M1~~ | ~~Verify GLM-4.7 peak-hour timer~~ | **OBSOLETE** — Z.AI/GLM provider fully removed 2026-07-15. No GLM models in cluster. |
| M2 | Monitor vLLM 200K context + maxConcurrency 16 for OOM | Monitor ongoing |

---

## Recently Completed

| # | Item | What |
|---|------|------|
| ✅ | JCCF actor + RSS added | Influence module: canadian-ngo, RSS wired |
| ✅ | Katzilla references removed | 5 docs, 3 code files, competitive analysis |
| ✅ | Dev funnel Ingresses created + affinity fixed | Spread nexus/sentry/forge, zephyr excluded |
| ✅ | Corporate + influence modules built | 2,850 lines: lobbying, procurement, execs, actors |
| ✅ | Media execs expanded | 17 tracked execs across 3 sectors |
| ✅ | Data source expansion plan written | 7 modules + oversight, 4 phases |
| ✅ | K8s Tailscale Funnel live | 5 ingresses (3 dev, 2 prod) via operator, ProxyGroup 2/2, host funnel disabled |
| ✅ | Funnel manifests committed to Nix | /etc/nixos/kubernetes-manifests/tailscale/ — all 5 YAML files |
| ✅ | **vLLM on Nexus fixed** | Restored nix-csi scratch container deployment using vllm-turboquant-env from /data/projects/own/vllm |

---

## Decision Log

| Decision | Rationale | Date |
|----------|-----------|------|
| **K8s Tailscale Funnel via operator (not host)** | Operator resolved — ProxyGroup synced, 5 ingresses working, all manifests in Nix source of truth. Host funnel disabled. | May 14 |
| **Security: NodePort restriction (P1) prioritized over secrets encryption (P0)** | 17 NodePorts actively bypass auth today. Secrets in plaintext are higher blast radius but lower immediate risk in single-operator homelab. | May 14 |
| **Dev Ingresses exclude zephyr** | zephyr 31GB RAM, constant OOM risk. Dev instances belong on nexus/sentry/forge. | May 14 |
| **Use nix-csi for vLLM instead of OCI image** | OCI image `nexus:5000/vllm-turboquant:0.20.0` never built. nix-csi scratch container with host `/nix` store mount works immediately with existing vllm-turboquant-env derivation. | May 16 |

---

*Generated 2026-05-14. Last items completed: JCCF integration, Katzilla purge, Funnel live, Nix funnel manifests.*
